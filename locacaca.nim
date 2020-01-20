import cmd, discord/[discord, arguments, http, messages, ws]

import strutils, json, asyncdispatch, asyncnet, httpclient, times, uri, tables, random, os, macros

proc evalNim(code: string): tuple[compileLog, log: string] {.used.} =
  let http = newAsyncHttpClient()
  try:
    let js = %*{"code": code, "compilationTarget": "c"}
    let resp = waitFor http.post("https://play.nim-lang.org/compile", $js)
    let res = parseJson(waitFor resp.body)
    result = (res["compileLog"].getStr, res["log"].getStr)
  except:
    result = ("", "")
  http.close()

proc evalGroovy(code: string): tuple[result, output, stacktrace: string, errorcode: string] {.used.} =
  let http = newAsyncHttpClient()
  try:
    let resp = waitFor http.request("https://groovyconsole.appspot.com/executor.groovy?script=" & encodeUrl(code), HttpPost,
      "{}")
    result.errorcode = $resp.code & "\n" & waitFor resp.body
    let res = parseJson(waitFor resp.body)
    result.result = res["executionResult"].getStr
    result.output = res["outputText"].getStr
    result.stacktrace = res["stacktraceText"].getStr
  except:
    discard
  http.close()

cmd "cmds":
  info "lists all commands"
  var res = "do v<info cmd for usage:"
  for c, _ in nameInfoTable.items:
    res.add(' ')
    res.add(c)
  asyncCheck respond(res)

cmd "info":
  info "gives info about the bot, or about a command if you ask"
  if args.len == 0:
    asyncCheck respond("""this is claudes bot, you call it by doing v<command
for all commands do v<cmds
why did i choose v<? because i dont have to press shift or ctrl or whatever to type it
normally id go with something like "poo " but itd come out of nowhere if someone typed poo naturally
source code at https://github.com/hlaaftana/pkpsgpsg
nim version is """ & NimVersion)
  else:
    for c, i in nameInfoTable.items:
      if c == args:
        if i.len == 0:
          asyncCheck respond("no info about that command")
        else:
          asyncCheck respond(args & ": " & i)
        return
    asyncCheck respond("couldnt find command " & args)

cmd "say":
  info "copies you"
  asyncCheck respond(args)

when false:
  cmd "save":
    info """lets you save snippets of text
            usage:
            `save set name text  -- saves text to name. note that you can use $1 to replace text,
                              -- so to append you could do "save set name $1 newtext"
            save get name       -- gets text of name
            save get name ID    -- gets text of name from saves of person with ID, ID can also be "anyone" or "me"
            save delete name    -- deletes text from name
            save list           -- lists your saves
            save list ID        -- lists saves of person with ID, can also be anyone or me`""".unindent

    var a = newArguments(args)
    let arg = a.next
    case arg
    of "get":
      let name = escapeJson(a.next)[1..^2]
      var by: string
      case a.rest
      of "", "me":
        by = JsonNode(message)["author"]["id"].getStr
      of "anyone":
        by = ""
      elif a.rest.allCharsInSet({'0'..'9'}):
        by = a.rest
      else:
        asyncCheck respond("the second argument is supposed to be an ID, " &
          "you must have put in a space by accident. to keep the spaces, put the name of the save in quotes")
        return
      var file = open("data/saved")
      var ourId = false
      for line in file.lines:
        case line[0]
        of '0'..'9':
          ourId = by == "" or line == by
        of '|':
          if ourId:
            var escaped = false
            var recorded = ""
            for i in 1..line.high:
              let ch = line[i]
              if not escaped and ch == '"':
                if recorded == name:
                  asyncCheck respond(name & ": " & parseJson(line[i..^1]).getStr)
                  file.close()
                  return
                else: break
              recorded.add(ch)
              escaped = not escaped and ch == '\\'
        else:
          discard
      file.close()
      asyncCheck respond("couldnt find " & name)
    of "set":
      let name = escapeJson(a.next)[1..^2]
      let val = a.rest
      var str = ""
      let ourId = JsonNode(message)["author"]["id"].getStr
      var isOurId = false
      var done = false
      for line in "data/saved".lines:
        if done:
          str.add(line)
          str.add("\n")
        else:
          case line[0]
          of '0'..'9':
            if isOurId:
              str.add("|" & name & $(%val) & "\n")
              str.add("\n")
              done = true
            else:
              isOurId = line == ourId
            str.add(line)
            str.add("\n")
          of '|':
            var
              i = 1
              n = ""
              escaped = false
            while i < line.len:
              let ch = line[i]
              if not escaped and ch == '"':
                break
              else:
                n.add(ch)
              escaped = not escaped and ch == '\\'
              inc i
            if name == n:
              str.add("|" & name & $(%(val % parseJson(line[i .. ^1]).getStr)) & "\n")
              done = true
            else:
              str.add(line)
            str.add("\n")
          elif not line.allCharsInSet(Whitespace):
            str.add(line.strip)
            str.add("\n")
      if not done:
        if not isOurId:
          str.add(ourId)
          str.add("\n")
        str.add("|" & name & $(%val) & "\n")
        str.add("\n")
      writeFile("data/saved", str)
      asyncCheck respond("saved to " & name)
    of "delete":
      let name = escapeJson(a.next)[1..^2]
      var str = ""
      let ourId = JsonNode(message)["author"]["id"].getStr
      var isOurId, successful, done = false
      for line in "data/saved".lines:
        if done:
          str.add(line)
          str.add("\n")
        else:
          case line[0]
          of '0'..'9':
            if isOurId:
              done = true
            else:
              isOurId = line == ourId
            str.add(line)
            str.add("\n")
          of '|':
            var
              i = 1
              n = ""
              escaped = false
            while i < line.len:
              let ch = line[i]
              if not escaped and ch == '"':
                break
              else:
                n.add(ch)
              escaped = not escaped and ch == '\\'
              inc i
            if name != n:
              str.add(line)
              str.add("\n")
            else:
              successful = true
          else:
            str.add(line)
            str.add("\n")
      writeFile("data/saved", str)
      if successful:
        asyncCheck respond("deleted " & name)
      else:
        asyncCheck respond(name & " didn't exist")
    of "list":
      var by: string
      case a.rest
      of "", "me":
        by = JsonNode(message)["author"]["id"].getStr
      of "anyone":
        by = ""
      elif a.rest.allCharsInSet({'0'..'9'}):
        by = a.rest
      else:
        asyncCheck respond("list is supposed to take an ID, " &
          "you must have put in a name or whatever, i dont like those yet")
        return
      var ourId = false
      var names = newSeq[string]()
      for line in "data/saved".lines:
        case line[0]
        of '0'..'9':
          ourId = by == "" or line == by
        of '|':
          if ourId:
            var escaped = false
            var recorded = ""
            for i in 1..line.high:
              let ch = line[i]
              if not escaped and ch == '"':
                names.add(recorded)
                break
              recorded.add(ch)
              escaped = not escaped and ch == '\\'
        else:
          discard
      if names.len != 0:
        asyncCheck respond("got names: " & names.join(", "))
      elif by != "":
        asyncCheck respond(by & " had no saves")
      else:
        asyncCheck respond("no one had saves (?)")
    else:
      asyncCheck respond("do v<info save")

cmd "gccollect":
  GC_fullCollect()

cmd "die":
  if JsonNode(message)["author"]["id"].getStr == "98457401363025920":
    quit(-1)
  else:
    asyncCheck respond("i cant die,")

cmd "ping":
  var msg = "started"
  let a = cpuTime()
  let m = waitFor respond(msg)
  let b = cpuTime()
  let mbody = waitFor m.body
  msg.add("\nposting took " & $(b - a) & " seconds")
  let c = cpuTime()
  let mn = parseJson(mbody)
  discard waitFor(instance.http.edit(mn, msg))
  let d = cpuTime()
  msg.add("\nediting took " & $(d - c) & " seconds")
  asyncCheck instance.http.edit(mn, msg)

cmd "nim+":
  info "compiles nim code via the playground and shows the compile output"
  typing
  let (compileLog, log) = evalNim(args)
  if log.len == 0:
    asyncCheck respond("try again later the nim playground is shaky")
  else:
    asyncCheck respond("compile log:\n" & compileLog & "\noutput:\n" & log)

cmd "nim":
  info "compiles nim code via the playground, for compile output use nim+"
  typing
  let log = evalNim(args)[1]
  if log.len == 0:
    asyncCheck respond("try again later the nim playground is shaky")
  else:
    asyncCheck respond("output:\n" & log)

cmd "groovy":
  info "evaluates groovy code via groovyconsole.appspot.com"
  typing
  let (result, output, stack, errorcode) = evalGroovy(args)
  var msg = ""
  if result.len != 0:
    msg.add("result:\n")
    msg.add(result)
    msg.add("\n")
  if output.len != 0:
    msg.add("output:\n")
    msg.add(output)
    msg.add("\n")
  if stack.len != 0:
    msg.add("stacktrace:\n")
    msg.add(stack)
    msg.add("\n")
  if msg.len == 0:
    asyncCheck respond("got empty response: " & errorcode)
  else:
    asyncCheck respond(msg)

cmd "smashrand":
  info """makes a set of smash characters then picks by random and removes them
usage:
`smashrand` if no list exists, makes one with every character, otherwise picks from existing list
`smashrand show` shows existing list, or the default list if no list exists
`smashrand remove char` removes character from existing list, or makes a new list without the character
`smashrand clear` clears list
`smashrand without char1, char2` makes a new list without those characters"""

  const chars = ["Mario", "Donkey Kong", "Link", "Samus", "Dark Samus", "Yoshi", "Kirby", "Fox", "Pikachu", "Luigi", "Ness", "Captain Falcon", "Jigglypuff", "Peach", "Daisy", "Bowser", "Ice Climbers", "Sheik", "Zelda", "Dr. Mario", "Pichu", "Falco", "Marth", "Lucina", "Young Link", "Ganondorf", "Mewtwo", "Roy", "Chrom", "Mr. Game & Watch", "Meta Knight", "Pit", "Dark Pit", "Zero Suit Samus", "Wario", "Snake", "Ike", "Pokemon Trainer", "Diddy Kong", "Lucas", "Sonic", "King Dedede", "Olimar", "Lucario", "R.O.B.", "Toon Link", "Wolf", "Villager", "Mega Man", "Wii Fit Trainer", "Rosalina & Luma", "Little Mac", "Greninja", "Palutena", "Pac-Man", "Robin", "Shulk", "Bowser Jr.", "Duck Hunt", "Ryu", "Ken", "Cloud", "Corrin", "Bayonetta", "Inkling", "Ridley", "Simon Belmont", "Richter", "King K. Rool", "Isabelle", "Incineroar", "Piranha Plant", "Joker"]
  
  var chanId = message.channelId
  var a = newArguments(args)
  case a.next
  of "":
    try:
      let list = smashCharLists[chanId]
      randomize()
      let chIndex = rand(list.len - 1)
      let ch = list[chIndex]
      smashCharLists[chanId].del(chIndex)
      asyncCheck respond(ch)
    except KeyError:
      smashCharLists[chanId] = @chars
      asyncCheck respond("i made a new list for you BA!")
  of "show":
    asyncCheck respond(try: smashCharLists[chanId].join(", ") except: "Default list: " & chars.join(", "))
  of "remove":
    if not smashCharLists.hasKey(chanId):
      smashCharLists[chanId] = @chars
    for name in a.rest.split(','):
      let i = smashCharLists[chanId].find(name.strip)
      if i != -1: smashCharLists[chanId].del(i)
    asyncCheck respond("yes BA")
  of "clear":
    smashCharLists.del(chanId)
    asyncCheck respond("thats a good idea, BA")
  of "without":
    smashCharLists[chanId] = @chars
    for name in a.rest.split(','):
      let i = smashCharLists[chanId].find(name.strip)
      if i != -1: smashCharLists[chanId].del(i)
    asyncCheck respond("uh huh, BA")
  else:
    asyncCheck respond("what BA?")

proc filterText(text: string): string =
  result = text.multiReplace({
    "@everyone": "@\u200beveryone",
    "@here": "@\u200beveryone"
  })
  if result.len >= 1_700:
    result = "text is too big to post"

var
  ready: JsonNode
  instance: DiscordInstance
  smashCharLists: Table[string, seq[string]]

type OurDispatcher = object

proc spam() {.async.} =
  while not instance.ws.sock.isClosed:
    await sleepAsync(2000)
    instance.http.sendMessage("668846634326556672", "hello now at " & $now())

proc dispatch(dispatcher: OurDispatcher, event: string, node: JsonNode) {.gcsafe.} =
  case event
  of "READY":
    ready = node
    asyncCheck spam()
  of "MESSAGE_CREATE":
    let msg = MessageEvent(node)
    let cont = msg.content
    var curr = cont

    # identity check
    if node["author"]["id"] == ready["user"]["id"]:
      return

    template respond(cont: string, tts = false): untyped {.used.} =
      instance.http.reply(message, filterText(cont), tts)
    
    template typing(): untyped {.used.} =
      instance.http.sendTyping(message.channelId)

    # prefixes
    if curr.startsWith("v<"):
      curr.removePrefix("v<")
    else:
      return

    var arg = curr

    eachCommand(msg, cont, arg):
      if arg.startsWith(prefix):
        arg.removePrefix(prefix)
        let ended = arg.len == 0
        if ended or arg[0] in Whitespace:
          if not ended:
            arg = arg.strip(trailing = false)
          commandBody
          return
        arg = curr

proc main =
  let dispatcher = OurDispatcher()
  init(dispatcher, when defined(home): parseFile("bot.json")["token"].getStr else: getEnv("DISCORD_TOKEN"), instance)
  runForever()

main()
