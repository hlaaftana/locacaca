import macros, messages

type Command* = ref object
  name*, info*: string
  node*: NimNode

var commands* {.compileTime.}: seq[Command]

macro cmd*(name: untyped, body: untyped): untyped =
  let cmd = new(Command)
  expectKind name, {nnkIdent, nnkStrLit, nnkRStrLit, nnkTripleStrLit}
  cmd.name = name.strVal
  if body.kind == nnkStmtList:
    cmd.node = newStmtList()
    var infoSet = false
    for c in body:
      if not infoSet and c.kind in {nnkCommand, nnkCall, nnkCallStrLit} and
        c.len == 2 and c[0].kind == nnkIdent and c[0].strVal == "info" and
        c[1].kind in {nnkStrLit, nnkRStrLit, nnkTripleStrLit}:
        cmd.info = c[1].strVal
        infoSet = true
      else:
        cmd.node.add(c)
  else:
    cmd.node = body
  commands.add(cmd)

macro nameInfoTable*: seq[(string, string)] =
  var t = newSeq[(string, string)](commands.len)
  for i in 0..<commands.len:
    t[i] = (commands[i].name, commands[i].info)
  result = newLit(t)

macro commandBody*(name: static[string]): untyped =
  for c in commands:
    if c.name == name: return c.node

macro eachCommand*(message: MessageEvent, content, args: string, body: untyped): untyped =
  result = newStmtList()
  for c in commands:
    let name = c.name
    let node = c.node
    result.add(quote do:
      block:
        const prefix {.used, inject.} = `name`
        template commandBody: untyped {.used.} =
          let message {.inject, used.} = `message`
          let content {.inject, used.} = `content`
          let args {.inject, used.} = `args`
          `node`
        `body`)
  result = newBlockStmt(result)
