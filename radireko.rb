require 'open-uri'
require 'rexml/document'
require 'yaml'

require_relative './configs'

class Radireko

  RADIKO_PROGRAM_URL = "http://radiko.jp/v2/api/program"
  RADIKO_PROGRAM_URL_TODAY = "#{RADIKO_PROGRAM_URL}/today?area_id=#{RADIREKO_CONFIG[:radiko_area_id]}"
  RADIKO_PROGRAM_URL_TOMORROW = "#{RADIKO_PROGRAM_URL}/tomorrow?area_id=#{RADIREKO_CONFIG[:radiko_area_id]}"

  TODAY_XML_PATH    = "#{ROOT_DIR}/#{RADIREKO_CONFIG[:radiko_area_id]}_today.xml"
  TOMORROW_XML_PATH = "#{ROOT_DIR}/#{RADIREKO_CONFIG[:radiko_area_id]}_tomorrow.xml"

  def initialize
    begin
      fetch_program_list if program_info_is_old?
    rescue
    end
    @keywords = YAML.load_file(File.dirname(__FILE__) + "/keywords.yaml")
  end

  def run
    program_list = REXML::Document.new(open(TODAY_XML_PATH))
    stations = REXML::XPath.match(program_list, '/radiko/stations/station').each do |station_info|
      REXML::XPath.match(station_info, "scd/progs/prog").each do |program_info|
        if broadcasting_soon?(program_info) && program_info_include_keywords?(program_info)
          sid      = station_info.attributes['id']
          duration = program_info.attributes['dur'].to_i + (RADIREKO_CONFIG[:magic_sec] + RADIREKO_CONFIG[:prepare_record_sec])
          title    = REXML::XPath.first(program_info, 'title').text
          from     = program_info.attributes['ft']
          do_record(sid, duration, "#{from}_#{title}", RADIREKO_CONFIG[:rec_dir])
        end
      end
    end
  end

  private
  def program_info_is_old?
    return true if !File.exist?(TODAY_XML_PATH)

    program_list = REXML::Document.new(open(TODAY_XML_PATH))
    return true if REXML::XPath.first(program_list, '/radiko/ttl').text.to_i +
      REXML::XPath.first(program_list, '/radiko/srvtime').text.to_i < Time.now.to_i
  end

  def fetch_program_list
    open(TODAY_XML_PATH, 'wb') do |f|
      open(RADIKO_PROGRAM_URL_TODAY) do |xml|
        f.write(xml.read)
      end
    end

    open(TOMORROW_XML_PATH, 'wb') do |f|
      open(RADIKO_PROGRAM_URL_TOMORROW) do |xml|
        f.write(xml.read)
      end
    end
  end

  def broadcasting_soon?(program_info_parsed_xml)
    from = Time.strptime(program_info_parsed_xml.attributes['ft'] + "+0900", "%Y%m%d%H%M%S%z")
    from.to_i - (RADIREKO_CONFIG[:prepare_record_sec]) <= Time.now.to_i && Time.now.to_i < from.to_i
  end

  def program_info_include_keywords?(program_info_parsed_xml)
    %w!title sub_title info desc!.map{|elem|
      val = REXML::XPath.first(program_info_parsed_xml, elem).text
      if val
        @keywords.map{|keyword| val.include?(keyword)}.include?(true)
      else
        false
      end
    }.include?(true)
  end

  def do_record(sid, duration, filename, out_dir = ROOT_DIR)
    cmd = "#{ROOT_DIR}/rec_radiko.sh #{sid} #{duration} \"#{filename}\" #{out_dir} > \"#{out_dir}/#{filename}.txt\" 2>&1"
    puts cmd
    pid = spawn(cmd)
    Process.detach(pid)
  end
end

while true
  Radireko.new.run
  sleep(RADIREKO_CONFIG[:prepare_record_sec])
end
