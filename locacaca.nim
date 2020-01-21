import discord/[discord, http, messages, commands], websocket, locks

import strutils, json, asyncdispatch, httpclient, tables, os, times

include cmds

proc filterText(text: string): string =
  result = text.multiReplace({
    "@everyone": "@\u200beveryone",
    "@here": "@\u200beveryone"
  })
  if result.len >= 1_700:
    result = "text is too big to post"

type OurDispatcher = object

let token =
  when defined(home):
    parseFile("bot.json")["token"].getStr
  else:
    getEnv("DISCORD_TOKEN")

var
  ready: JsonNode
  startTime: DateTime
  ws: AsyncWebSocket
  hc: AsyncHttpClient
  hcLock: Lock
  tokenHeaders: HttpHeaders
  smashCharLists: Table[string, seq[string]]

proc queueResetHttp {.async.} =
  await sleepAsync(40_000)
  withLock hcLock: hc = nil

proc dispatch(dispatcher: OurDispatcher, event: string, node: JsonNode) =
  case event
  of "READY":
    ready = node
    echo "readied"
    startTime = now()
  of "MESSAGE_CREATE":
    let msg = MessageEvent(node)
    let cont = msg.content
    var curr = cont

    # identity check
    if node["author"]["id"] == ready["user"]["id"]:
      return
    
    initLock(hcLock)
    
    template createHttp() =
      if unlikely(hc.isNil):
        hc = newHttp(tokenHeaders)
        when not defined(home):
          asyncCheck queueResetHttp()

    template respond(cont: string, tts = false): untyped {.used.} =
      hc.reply(message, filterText(cont), tts)
    
    template typing(): untyped {.used.} =
      hc.sendTyping(message.channelId)

    # prefixes
    if curr.startsWith("v<"):
      curr.removePrefix("v<")
    elif curr.startsWith("vv "):
      curr.removePrefix("vv ")
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
          acquire(hcLock)
          createHttp()
          commandBody
          release(hcLock)
          return
        arg = curr

proc main =
  let dispatcher = OurDispatcher()
  init(dispatcher, token, tokenHeaders, ws)
  runForever()

main()
