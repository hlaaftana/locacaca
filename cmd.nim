import macros, discord/messages

type Command* = ref object
  name*, info*: string
  node*: NimNode

var commands* {.compileTime.}: seq[Command]

macro cmd*(name: untyped, body: untyped): untyped =
  let cmd = new(Command)
  if name.kind in {nnkIdent, nnkStrLit, nnkRStrLit, nnkTripleStrLit}:
    cmd.name = name.strVal
  else:
    error("not a command name", name)
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

proc withPragmas(name: string, pragmas: varargs[string]): NimNode =
  var prags = newNimNode(nnkPragma)
  for p in pragmas:
    prags.add(ident(p))
  result = newTree(nnkPragmaExpr, ident(name), prags)

macro eachCommand*(message: MessageEvent, content, args: string, body: untyped): untyped =
  result = newStmtList()
  for c in commands:
    let n = newStmtList()
    n.add(
      newTree(nnkConstSection,
        newTree(nnkConstDef, withPragmas("prefix", "used"), newEmptyNode(), newLit(c.name))))
    let b = newStmtList(
      newTree(nnkLetSection,
        newTree(nnkIdentDefs,
          withPragmas("message", "inject", "used"),
          newEmptyNode(),
          message),
        newTree(nnkIdentDefs,
          withPragmas("content", "inject", "used"),
          newEmptyNode(),
          content),
        newTree(nnkIdentDefs,
          withPragmas("args", "inject", "used"),
          newEmptyNode(),
          args)),
      c.node)
    n.add(newProc(ident"commandBody", [bindSym"untyped"], b, nnkTemplateDef,
      newTree(nnkPragma, ident"used")))
    n.add(body)
    result.add(newBlockStmt(n))
