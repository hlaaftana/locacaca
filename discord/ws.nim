import
  websocket, asyncdispatch, asyncnet, uri, net, common, tables, json

when compress:
  from zip/zlib import uncompress

when encoding == DiscordEncoding.etf:
  import etf
else:
  proc send*(ws: AsyncWebSocket, data: JsonNode) {.async.} =
    await ws.sendText($data)

  template send(ws: AsyncWebSocket, op: int, data: untyped): auto =
    ws.send(%*{
      "op": op,
      "d": data
    })

proc identify*(ws: AsyncWebSocket, token: string) {.async.} =
  when encoding == DiscordEncoding.etf:
    asyncCheck ws.sendText(toBytes(Term(tag: tagMap, map: @[
      (Term(tag: tagAtomUtf8, atom: "op".Atom), Term(tag: tagUint8, u8: 2)),
      (Term(tag: tagAtomUtf8, atom: "d".Atom), Term(tag: tagMap, map: @[
        (Term(tag: tagAtomUtf8, atom: "token".Atom), Term(tag: tagString, str: token)),
        #(Term(tag: tagAtomUtf8, atom: "compress".Atom), Term(tag: tagUint8, u8: compress.byte)),
        (Term(tag: tagAtomUtf8, atom: "large_threshold".Atom), Term(tag: tagUint8, u8: 250)),
        (Term(tag: tagAtomUtf8, atom: "properties".Atom), Term(tag: tagMap, map: @[
          (Term(tag: tagAtomUtf8, atom: "$os".Atom), Term(tag: tagString, str: hostOS)),
          (Term(tag: tagAtomUtf8, atom: "$browser".Atom), Term(tag: tagString, str: "Nim")),
          (Term(tag: tagAtomUtf8, atom: "$device".Atom), Term(tag: tagString, str: "Nim"))]))]))])), masked = true)
  else:
    asyncCheck ws.send(op = 2, {
      "token": token,
      "compress": defined(discordCompress),
      "large_threshold": 250,
      "properties": {
        "$os": hostOS,
        "$browser": "Nim",
        "$device": "Nim"
      }
    })

proc heartbeat*(ws: AsyncWebSocket, lastSeq: int, interval: int) {.async.} =
  while not ws.sock.isClosed:
    when encoding == DiscordEncoding.etf:
      asyncCheck ws.sendText(toBytes(Term(tag: tagMap, map: @[
        (Term(tag: tagAtomUtf8, atom: "op".Atom), Term(tag: tagUint8, u8: 1)),
        (Term(tag: tagAtomUtf8, atom: "d".Atom), Term(tag: tagInt32, i32: lastSeq.int32))])))
    else:
      asyncCheck ws.send(op = 1, lastSeq)
    await sleepAsync(interval)

when encoding == DiscordEncoding.etf:
  proc process*[T](dispatcher: T, ws: AsyncWebSocket, token: string, lastSeq: ref int, data: Term) =
    echo data

proc process*[T: Dispatcher](dispatcher: T, ws: AsyncWebSocket, token: string, lastSeq: ref int, data: JsonNode) =
  let op = data["op"].getInt()
  case op
  of 0:
    lastSeq[] = data["s"].getInt()
    let
      d = data["d"]
      t = data["t"].getStr()
    if t == "READY": echo "readied"
    dispatcher.dispatch(t, d)
  of 10:
    echo "heartbeating & identifying"
    asyncCheck heartbeat(ws, lastSeq[], data["d"]["heartbeat_interval"].getInt)
    asyncCheck identify(ws, token)
  else: discard

proc read*[T: Dispatcher](dispatcher: T, ws: AsyncWebSocket, token: string, lastSeq: ref int) {.async.} =
  while not ws.sock.isClosed:
    let (opcode, data) = await ws.readData()
    when encoding == DiscordEncoding.etf: echo data
    case opcode
    of Opcode.Text:
      when encoding == DiscordEncoding.etf:
        if data[0] == 131.char:
          let etf = parseEtf(data)
          echo data
          echo "data: ", cast[seq[byte]](data)
          echo (if etf.isNil: "nil" else: $(etf[]))
        else:
          let json = parseJson(data)
          process dispatcher, ws, token, lastSeq, json
      else:
        let json = parseJson(data)
        process dispatcher, ws, token, lastSeq, json
    of Opcode.Binary:
      when defined(discordCompress):
        let text = uncompress(data)
        if text.isNil:
          echo "Decompression failed, ignoring"
        else:
          process dispatcher, ws, token, lastSeq, parseJson(text)
    of Opcode.Close:
      echo "closed: ", extractCloseData(data)
      ws.sock.close()
    else: continue
