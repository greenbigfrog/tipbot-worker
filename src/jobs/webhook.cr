class TB::Worker::WebhookJob < Mosquito::QueuedJob
  params embed : String, username : String, avatar_url : String, webhook_type : String
  throttle limit: 1, period: 5

  def perform
    case webhook_type
    when "admin"   then webhook = ENV["ADMIN_WEBHOOK"]
    when "general" then webhook = ENV["GENERAL_WEBHOOK"]
    else                raise "Invalid webhook type"
    end

    json = "{\"avatar_url\": \"#{avatar_url}\", \"username\": \"#{username}\", \"embeds\": [#{embed}]}"
    res = HTTP::Client.post(webhook + "?wait=true", HTTP::Headers{"Content-Type" => "application/json"}, json)
    raise "Error posting to webhook: #{res.body}" unless res.success?
  end
end
