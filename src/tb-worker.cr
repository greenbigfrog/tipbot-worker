require "mosquito"
require "discordcr"
require "big"
require "http/client"
require "logger"

require "tb"
require "./jobs/*"

Mosquito.configure do |settings|
  settings.redis_url = ENV["REDIS_URL"]
end
