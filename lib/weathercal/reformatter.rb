# curl 'https://www.jma.go.jp/bosai/forecast/data/forecast/130000.json?__time__=20210225184954' > tokyo.json
# 2021-02-25T20:48:53+09:00 に取得したときは reportDatetime は 2021-02-25T17:00:00+09:00
# 2021-02-26T01:46:39+09:00 も同じ
# 2021-02-26T09:16:40+09:00 に取得で 2021-02-26T05:00:00+09:00
require "json"

module Weathercal
  module Reformatter
    module StrictAccessor
      def [](key_or_index)
        fetch(key_or_index)
      end
    end

    class << self
      def reformat(forecast)
        json = strictify(forecast)

        first, second = json
        assert { first["publishingOffice"] == second["publishingOffice"] }
        meta = {
          publishingOffice: first["publishingOffice"],
          reportDatetime: first["reportDatetime"],
          reportDatetimeForWeek: second["reportDatetime"],
        }

        recent_weathers, recent_pops, recent_temps = first["timeSeries"]
        week_weather_and_pops, week_temps = second["timeSeries"]
        # temp_averages = second["tempAverage"]
        # precip_average = second["precipAverage"]
        number_of_areas = recent_weathers["areas"].size
        meta[:number_of_areas] = number_of_areas
        assert { number_of_areas == recent_pops["areas"].size }
        assert { number_of_areas == recent_temps["areas"].size }

        areas = number_of_areas.times.map do |i|
          per_six_hours_records = Hash.new {|h, k| h[k] = {} }
          three_days_records = Hash.new {|h, k| h[k] = {} }
          day_records = Hash.new {|h, k| h[k] = {} }
          week_records = Hash.new {|h, k| h[k] = {} }
          area = {}

          # recent_weather
          recent_weather = recent_weathers["areas"][i]
          area[:region_name] = recent_weather["area"]["name"]
          area[:region_code] = recent_weather["area"]["code"]
          recent_weathers["timeDefines"].each_with_index do |time, j|
            three_days_records[time][:weather_code] = recent_weather["weatherCodes"][j]
            three_days_records[time][:weather] = recent_weather["weathers"][j]
            three_days_records[time][:wind] = recent_weather["winds"][j]
            # waves は地域によってない場合がある
            three_days_records[time][:wave] = recent_weather.has_key?("waves") ? recent_weather["waves"][j] : nil
          end

          # recent_pop
          recent_pop = recent_pops["areas"][i]
          assert { area[:region_name] == recent_pop["area"]["name"] }
          assert { area[:region_code] == recent_pop["area"]["code"] }
          recent_pops["timeDefines"].each_with_index do |time, j|
            per_six_hours_records[time][:pop] = recent_pop["pops"][j]
          end

          # recent_temps
          recent_temp = recent_temps["areas"][i]
          area[:point_name] = recent_temp["area"]["name"]
          area[:point_code] = recent_temp["area"]["code"]
          recent_temps["timeDefines"].each_with_index do |time, j|
            day_records[time][:temp] = recent_temp["temps"][j]
          end

          # week_weather_and_pop
          week_weather_and_pop = week_weather_and_pops["areas"][i]
          assert { area[:region_name] == week_weather_and_pop["area"]["name"] }
          assert { area[:region_code] == week_weather_and_pop["area"]["code"] }
          week_weather_and_pops["timeDefines"].each_with_index do |time, j|
            week_records[time][:weather_code] = week_weather_and_pop["weatherCodes"][j]
            week_records[time][:pop] = week_weather_and_pop["pops"][j]
            week_records[time][:reliability] = week_weather_and_pop["reliabilities"][j]
          end

          # week_temp
          week_temp = week_temps["areas"][i]
          assert { area[:point_name] == week_temp["area"]["name"] }
          assert { area[:point_code] == week_temp["area"]["code"] }
          week_temps["timeDefines"].each_with_index do |time, j|
            week_records[time][:temp_min] = week_temp["tempsMin"][j]
            week_records[time][:temp_min_upper] = week_temp["tempsMinUpper"][j]
            week_records[time][:temp_min_lower] = week_temp["tempsMinLower"][j]
            week_records[time][:temp_max] = week_temp["tempsMax"][j]
            week_records[time][:temp_max_upper] = week_temp["tempsMaxUpper"][j]
            week_records[time][:temp_max_lower] = week_temp["tempsMaxLower"][j]
          end

          # sort
          area[:per_six_hours_records] = per_six_hours_records.keys.sort.each_with_object({}) do |k, h|
            h[k] = per_six_hours_records[k]
          end
          area[:day_records] = day_records.keys.sort.each_with_object({}) do |k, h|
            h[k] = day_records[k]
          end
          area[:three_days_records] = three_days_records.keys.sort.each_with_object({}) do |k, h|
            h[k] = three_days_records[k]
          end
          area[:week_records] = week_records.keys.sort.each_with_object({}) do |k, h|
            h[k] = week_records[k]
          end
          area
        end

        strictify(meta.merge(areas: areas))
      end

      private
      def strict(object)
        object.extend(StrictAccessor)
      end

      def strictify(o)
        case o
        when Array
          strict(o.map {|e| strictify(e) })
        when Hash
          strict(o.each_with_object({}) {|(k, v), h| h[k] = strictify(v) })
        else
          o
        end
      end

      def assert(&block)
        unless block.call
          raise "Assertion failed"
        end
      end
    end
  end
end

# ruby lib/weathercal/reformatter.rb tokyo.20210225170000.json
if $0 == __FILE__
  forecast = JSON.parse(ARGF.read)
  h = Weathercal::Reformatter.reformat(forecast)
  puts JSON.pretty_generate(h)
end
