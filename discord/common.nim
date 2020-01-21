import uri

type
  DiscordEncoding* {.pure.} = enum
    json, etf

const
  discordUserAgent* = "locacaca (1.0 https://github.com/hlaaftana/locacaca)"
  api* = "https://discordapp.com/api/v6/".parseUri()
  encoding* = when defined(discordetf): DiscordEncoding.etf else: DiscordEncoding.json
  compress* = defined(discordCompress)
  messageEvent* = "MESSAGE_CREATE"
