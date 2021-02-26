$LOAD_PATH.unshift(File.expand_path(File.join(__dir__, "lib")))
require "weathercal/updater"

def update(event:, context:)
  Weathercal::Updater.update(bucket_name: BUCKET_NAME, debug: DEBUG)
end

DEBUG = !ENV["DEBUG"].nil?
BUCKET_NAME = ENV.fetch("BUCKET_NAME")

update(event: nil, context: nil) if DEBUG
