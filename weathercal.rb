require "open-uri"
require "nokogumbo"
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

def fetch(url)
  html = OpenURI.open_uri(url, &:read)
  Nokogiri.HTML5(html)
end

def weather_text(s)
  s = s.dup
  WEATHER_TEXT.each {|a, b| s.gsub!(a, b) }
  s
end

def parse_and_save_ical(doc, today)
  forecast_top_list_trs = doc.css("table.forecast-top > tbody > tr")
  first_day = forecast_top_list_trs[0].css("th")[1].inner_text.to_i
  first_date = case first_day
  when today.day
    today
  when (today + 1).day
    today + 1
  else
    raise "Unknown day #{first_day} on #{today}"
  end

  days = (first_date..(first_date + 6)).to_a

  forecast_top_list_trs[1..].each_slice(5) do |trs|
    weather_tr, rain_tr, reliability_tr, temp_max_tr, temp_min_tr = trs
    next unless rain_tr&.text["降水確率"]

    data = {}
    data[:location] = temp_max_tr.css(".cityname").inner_text.strip
    data[:forecasts] = days.zip(
      weather_tr.css(".for").to_a,
      rain_tr.css(".for").to_a,
      temp_max_tr.css(".for").to_a,
      temp_min_tr.css(".for").to_a,
    ).map {|(day, weather, rain, temp_max, temp_min)|
      forecast = {}
      forecast[:day] = day
      forecast[:weather] = weather.css("img").first["alt"]
      forecast[:mintemp] = temp_min.css(".mintemp").first.inner_text.strip.to_i
      forecast[:maxtemp] = temp_max.css(".maxtemp").first.inner_text.strip.to_i
      forecast[:rain] = rain.css(".pop").first.inner_text.strip.split("/").map {|s| "#{s}%" }.join("/")
      forecast
    }

    cal = Icalendar::Calendar.new
    cal.x_wr_calname = "週間天気予報 (#{data[:location]})"
    data[:forecasts].each do |f|
      cal.event do |e|
        e.dtstart = Icalendar::Values::Date.new(f[:day])
        e.summary = weather_text(f[:weather])
        e.description = "#{f[:mintemp]}℃/#{f[:maxtemp]}℃ #{f[:weather]} (☂#{f[:rain]})"
      end
    end
    save("#{data[:location]}.ics", cal.to_ical)
    save("#{data[:location]}.ical", cal.to_ical) # 最初このURLで提供していたため一応作成
  end
end

def update(event:, context:)
  save("index.html", INDEX_HTML)
  save("error.html", ERROR_HTML)

  today = Time.now.getlocal("+09:00").to_date
  (301..356).each do |num|
    url = "http://www.jma.go.jp/jp/week/#{num}.html"
    doc = fetch(url)
    parse_and_save_ical(doc, today)
  end

  {
    statusCode: 200,
    body: {
      message: 'Go Serverless v1.0! Your function executed successfully!',
      input: event
    }.to_json
  }
end
