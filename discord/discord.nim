import websocket, httpclient, common, http, ws, asyncdispatch, json, uri, strformat

proc fetchGateway*(http: AsyncHttpClient): string =
  let x = http.get(api / "gateway")["url"].getStr()
  result = x & ":443/?encoding=" & $encoding & "&v=6"

template init*[T](dispatcher: T, token: string,
                  tokenHeaders: var HttpHeaders,
                  ws: var AsyncWebSocket) =
  tokenHeaders = newHttpHeaders({"Authorization": "Bot " & token})
  let gateway = fetchGateway(newHttp(tokenHeaders))
  ws = waitFor newAsyncWebsocketClient(gateway)
  asyncCheck read(dispatcher, ws, token, new(int))
