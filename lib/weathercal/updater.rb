require "open-uri"
require "nokogumbo"
require "icalendar"
require "aws-sdk-s3"
require "stringio"
require "erb"
require "weathercal/ical_builder"
require "yaml"

module Weathercal
  class Updater
    include ERB::Util

    INDEX_ERB = ERB.new(File.read("index.html.erb"), trim_mode: "-")

    ERROR_HTML = <<~HTML
    <!doctype html>
    <title>weathercal</title>
    HTML

    attr_reader :bucket_name, :debug

    def self.update(bucket_name:, debug: false)
      new(bucket_name: bucket_name, debug: debug).update
    end

    def initialize(bucket_name:, debug: false)
      @bucket_name = bucket_name
      @debug = debug
    end

    def s3
      @s3 ||= Aws::S3::Client.new
    end

    def save(key, body_as_string)
      if debug
        warn "-" * 40
        warn key
        warn "-" * 40
        warn body_as_string
        return
      end
      s3.put_object(
        acl: "public-read",
        body: StringIO.new(body_as_string),
        bucket: bucket_name,
        key: key,
      )
    end

    def fetch_html(url)
      logger.debug(type: "fetch_html", url: url)
      html = OpenURI.open_uri(url, &:read)
      Nokogiri.HTML5(html)
    end

    def fetch_json(url)
      logger.debug(type: "fetch_json", url: url)
      json = OpenURI.open_uri(url, &:read)
      JSON.parse(json)
    end

    def parse_and_save_ical(json)
      point_names = []
      IcalBuilder.new.build_icals(json) do |cal, point_name|
        point_names << point_name
        save("#{point_name}.ics", cal.to_ical)
        save("#{point_name}.ical", cal.to_ical) # 最初このURLで提供していたため一応作成
      end
      point_names
    end

    def update_weather_codes
      weather_codes = nil
      url = "https://www.jma.go.jp/bosai/#pattern=forecast&area_type=offices&area_code=011000"
      doc = fetch_html(url)
      doc.css("script").each do |script|
        next unless script.text["Const.TELOPS"]
        next unless script.text =~ /Const\.TELOPS=(\{.+?\})/

        json = $~.captures[0].gsub(/(\d+):/) { %("#{$1}":) }
        weather_codes = JSON.parse(json)
      end

      File.write("#{__dir__}/../../constants/weather_codes.yml", weather_codes.to_yaml)
      weather_codes
    end

    def update_areas(timestamp)
      areas = fetch_json("https://www.jma.go.jp/bosai/common/const/area.json?__time__=#{timestamp}")
      File.write("#{__dir__}/../../constants/areas.yml", areas.to_yaml)
      areas
    end

    # https://www.jma.go.jp/bosai/forecast/data/forecast/011000.json?__time__=202102240700
    def update
      now = Time.now.getlocal("+09:00")
      timestamp = now.strftime("%Y%m%d%H%M%S")

      update_weather_codes
      areas = update_areas(timestamp)
      point_names = []

      areas["offices"].each_key do |code|
        url = "https://www.jma.go.jp/bosai/forecast/data/forecast/#{code}.json?__time__=#{timestamp}"
        json = fetch_json(url)
        added = parse_and_save_ical(json)
        point_names.concat(added)
      end

      save("index.html", INDEX_ERB.result(binding))
      save("error.html", ERROR_HTML)

      {
        statusCode: 200,
        body: {
          message: 'Go Serverless v1.0! Your function executed successfully!',
          input: event
        }.to_json
      }
    end

    def logger
      @logger ||= begin
        logger = Logger.new($stdout)
        logger.level = debug ? Logger::Severity::DEBUG : Logger::Severity::INFO
        logger.formatter = -> (severity, datetime, _progname, message) {
          {
            severity: severity,
            time: datetime.to_i,
          }.merge(message).to_json + "\n"
        }
        logger
      end
    end
  end
end
