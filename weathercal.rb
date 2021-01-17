require "open-uri"
require "nokogiri"
require "icalendar"
require "aws-sdk-s3"
require "stringio"

DEBUG = !ENV["DEBUG"].nil?
BUCKET_NAME = ENV.fetch("BUCKET_NAME")
WEATHER_TEXT = {
  "晴れ" => "☀",
  "曇り" => "☁",
  "雪か雨" => "☃",
  "雨か雪" => "☃",
  "雨" => "☂",
  "雪" => "☃",
  "後時々" => "/",
  "後" => "/",
  "時々" => "/",
  "一時" => "/",
  "止む" => "☁",
}

INDEX_HTML = File.read("index.html")

ERROR_HTML = <<~HTML
<!doctype html>
<title>weathercal</title>
HTML


def s3
  @s3 ||= Aws::S3::Client.new
end

def save(key, body_as_string)
  if DEBUG
    warn "-" * 40
    warn key
    warn "-" * 40
    warn body_as_string
    return
  end
  s3.put_object(
    acl: "public-read",
    body: StringIO.new(body_as_string),
    bucket: BUCKET_NAME,
    key: key,
  )
end

def fetch
  html = OpenURI.open_uri("http://www.jma.go.jp/jp/week/", &:read)
  Nokogiri.parse(html)
end

def weather_text(s)
  s = s.dup
  WEATHER_TEXT.each {|a, b| s.gsub!(a, b) }
  s
end

def update(event:, context:)
  save("index.html", INDEX_HTML)
  save("error.html", ERROR_HTML)

  today = Time.now.getlocal("+09:00").to_date
  doc = fetch
  forecastlist_trs = doc.css("table.forecastlist tr")
  first_day = forecastlist_trs[0].css("th")[1].inner_text.to_i
  first_date = case first_day
  when today.day
    today
  when (today + 1).day
    today + 1
  else
    raise "Unknown day #{first_day} on #{today}"
  end

  days = (first_date..(first_date + 6)).to_a

  forecastlist_trs[1..].each do |tr|
    next if tr.css(".forecast").empty?

    data = {}
    tds = tr.css("td").to_a
    data[:location] = tds.first.inner_text.strip
    data[:forecasts] = tds[1..].zip(days).map do |(td, day)|
      forecast = {}
      forecast[:day] = day
      forecast[:weather] = td.css("img").first["alt"]
      forecast[:mintemp] = td.css(".mintemp").first.inner_text.strip.to_i
      forecast[:maxtemp] = td.css(".maxtemp").first.inner_text.strip.to_i
      forecast
    end

    cal = Icalendar::Calendar.new
    cal.x_wr_calname = "週間天気予報 (#{data[:location]})"
    data[:forecasts].each do |f|
      cal.event do |e|
        e.dtstart = Icalendar::Values::Date.new(f[:day])
        e.summary = weather_text(f[:weather])
        e.description = "#{f[:mintemp]}℃/#{f[:maxtemp]}℃ #{f[:weather]}"
      end
    end
    save("#{data[:location]}.ical", cal.to_ical)
  end

  {
    statusCode: 200,
    body: {
      message: 'Go Serverless v1.0! Your function executed successfully!',
      input: event
    }.to_json
  }
end


