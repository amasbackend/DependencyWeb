# frozen_string_literal: true

class PlayChainParserService
  ACTOR_REF_PATTERN = /([A-Z][A-Za-z0-9_:]*)/.freeze

  def parse(content)
    return [] if content.blank?

    plays = []
    play_buffer = nil

    content.each_line do |line|
      stripped = line.rstrip
      if stripped.match?(/^\s*play\s+/)
        plays.concat(parse_play_args(play_buffer)) if play_buffer
        play_buffer = stripped.sub(/^\s*play\s+/, "")
      elsif play_buffer && stripped.match?(/^\s+\S/)
        play_buffer = "#{play_buffer} #{stripped.strip}"
      else
        plays.concat(parse_play_args(play_buffer)) if play_buffer
        play_buffer = nil
      end
    end

    plays.concat(parse_play_args(play_buffer)) if play_buffer
    plays.uniq
  end

  private

  def parse_play_args(segment)
    return [] if segment.blank?

    segment.split(",").filter_map do |part|
      part = part.strip
      next if part.blank? || part.start_with?(":")

      match = part.match(ACTOR_REF_PATTERN)
      match&.[](1)
    end
  end
end
