#!/usr/bin/env ruby
require 'json'
require 'pry'
require 'open3'

def message(file, msg)
  puts(file)
  puts(msg)
  puts
end

dir = "."

files = Dir.glob("#{dir}/**/*.{mkv,avi,ts}")

data = files.map do |file|
  begin
    probe = %x[ffprobe -v quiet -print_format json -show_streams "#{file}"]
    probe_hash = JSON.parse(probe)
  rescue Exception => e
  ensure
    if !probe || !probe_hash || probe_hash.empty?
      message(file, "ffprobe failed: #{e ? e.message : 'unknown error'}")
      next
    end
  end
  [file, probe_hash]
end.compact.to_h

data.each do |file, probe|
  streams = probe['streams'].map do |stream|
# Some tags keys may be upper case
    tags = stream.fetch('tags',{}).map { |k,v| [k.downcase, v.downcase]}.to_h
    {idx: stream['index'], type: stream['codec_type'], lang: tags['language']}
  end.compact

  stream_groups = streams.group_by { |stream| stream[:type] }

#require 'pry'
#binding.pry

  eng_audio = stream_groups['audio'].select {|s| s[:lang] == 'eng'}
  audio = stream_groups['audio']

  other_streams = stream_groups.keys.select { |type| !%w[video audio subtitle].include?(type) }
  unless other_streams.empty?
    message(file, "Extra streams: #{other_streams.join(', ')}")
  end

  if eng_audio.count == audio.count
    message(file, 'All audio streams are English')
    next
  end

  if eng_audio.count == 0
    message(file, 'No English audio streams')
    next
  end

  mapping = streams.map do |stream|
    "-map 0:#{stream[:idx]}" if stream[:type] == 'video' || stream[:lang] == 'eng'
  end.compact.join(' ')

  file_match = /(.*)\.(.*)/i.match(file)
  new_file = "#{file_match[1]}__tmp__.#{file_match[2]}"
  old_file = "#{file_match[1]}__old__.#{file_match[2]}"

  cmd = "ffmpeg -v error -stats -i \"#{file}\" #{mapping} -disposition:a:0 default -c copy \"#{new_file}\""


  Open3.popen2e(cmd) do |stdin, stdout, wait_thr|
    puts(file)
    puts(cmd)
    while (data = stdout.read(10))
      print(data)
    end

    if wait_thr.value.success?
      File.rename(file, old_file)
      File.rename(new_file, file)
      File.delete(old_file)
      puts('All done')
      puts
    else
      puts("Unable to ffmpeg")
      puts
    end

  end

end