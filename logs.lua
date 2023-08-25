function DiscordLog(webhook, data)
  local webhook = webhook or "https://discord.com/api/webhooks/1141023306384941187/-QT_YRnfLjoR_571bH1F9FCeyLdJ5NHGJVVaKJYp4XUYMtvG7rbVFFMooP84uBcgsooj"
  local extraInfo = source and " Triggered by ID: "..source.."\nName: "..GetPlayerName(source).."\nIP: "..(GetPlayerEndpoint(source) or "unknown").."\n" or ""
  local embed = {
    {
      ['author'] = {
        ['name'] = "Quantum Scripts",
      },
      ['title'] = data.title or "Pandadrugs",
      ['description'] = extraInfo..(data.description or ""),
      ['color'] = data.colour or 16711680,
      ['fields'] = data.fields or nil,
      ['footer'] = {
        ['text'] = "Pandadrugs by Mr Crowley & J60",
      },
    }
  }
  PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode({embeds = embed}), {['Content-Type'] = 'application/json'})
end

DiscordLog(false, {title = "Script Started", description = "Panda Drugs Started.", colour = 5763719})
