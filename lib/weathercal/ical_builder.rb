require "json"
require "yaml"
require "time"
require "weathercal/reformatter"
require "icalendar"

module Weathercal
  class IcalBuilder
    WEATHER_EMOJI = {
      "晴" => "☀",
      "曇" => "☁",
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

    def weather_codes
      @weather_codes ||= YAML.load_file("#{__dir__}/../../constants/weather_codes.yml")
    end

    def weather_text(code)
      weather_codes[code][3]
    end

    def weather_emoji(code)
      s = weather_text(code).dup
      WEATHER_EMOJI.each {|a, b| s.gsub!(a, b) }
      s
    end

    def build_icals(forecast_json_object)
      raise ArgumentError, "block required" unless block_given?

      json = Reformatter.reformat(forecast_json_object)
      json[:areas].each do |area|
        data = {}
        data[:location] = area[:point_name]

        data[:forecasts] = area[:week_records].map do |day_str, weekday_record|
          day = Time.parse(day_str)
          forecast = {}
          forecast[:day] = day.to_date
          forecast[:weather] = weekday_record[:weather_code]
          forecast[:mintemp] = weekday_record[:temp_min] == "" ? nil : weekday_record[:temp_min]
          forecast[:maxtemp] = weekday_record[:temp_max] == "" ? nil : weekday_record[:temp_max]
          forecast[:rain] = weekday_record[:pop] == "" ? nil : weekday_record[:pop]
          forecast
        end

        cal = Icalendar::Calendar.new
        cal.x_wr_calname = "週間天気予報 (#{data[:location]})"
        data[:forecasts].each do |f|
          cal.event do |e|
            e.dtstart = Icalendar::Values::Date.new(f[:day])
            e.summary = weather_emoji(f[:weather])

            description = []
            if f[:mintemp] && f[:maxtemp]
              description << "#{f[:mintemp]}℃/#{f[:maxtemp]}℃"
            end
            description << weather_text(f[:weather])
            description << "(☂#{f[:rain]})"
            e.description = description.join(" ")
          end
        end

        yield cal, data[:location]
      end
    end
  end
end

# ruby lib/weathercal/ical_builder.rb tokyo.20210225170000.json
if $0 == __FILE__
  forecast = JSON.parse(ARGF.read)
  Weathercal::IcalBuilder.new.build_icals(forecast) do |ical, point_name|
    puts "=" * 80
    puts point_name
    puts "=" * 80
    puts ical.to_ical
  end
end
