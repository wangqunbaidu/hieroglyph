require 'nokogiri'
require 'savage'

module Hieroglyph

  class Glyph

    attr_accessor :name, :path, :contents

    SHAPE_HANDLERS = {
      'circle' => 'report_invalid',
      'ellipse' => 'report_invalid',
      'line' => 'report_invalid',
      'polyline' => 'report_invalid',
      'rect' => 'report_invalid',
      'polygon' => 'convert_polygon',
      'path' => 'convert_path'
    }

    @@too_many_shapes = false
    @@shape_found = false

    def match(str, pattern_start, pattern, pattern_end)
    end

    def initialize(file, source, font)
      @font = font
      set_name(file, source)
      @contents = Nokogiri::XML(File.new(file))
      Hieroglyph.log "Parsing #{@name}", 2
      @path = parse_shapes
    end

    def set_name(file, source)
      @name = file.gsub(source, '').gsub('/', '')
      @name = @name.match(/^..*?(-|\.)/).to_s.chop
      unicode = @name.match(/^&#(x|X).*?;/).to_s.gsub(/^&#(x|X)/, '').gsub(/;/, '')
      unless unicode.empty?
        @font.unicode_values.push(unicode.to_s.upcase)
      else
        @font.characters.push(@name)
      end
    end

    def parse_shapes
      path = Savage::Path.new
      SHAPE_HANDLERS.each do |type, method|
        contents = @contents.root.css(type)
        unless contents.length == 0
          report_too_many if contents.length > 1
          report_too_many if @shape_found
          path = self.method(method).call(type, contents.first)
          @shape_found = true
        end
      end
      path
    end

    def convert_polygon(type, content)
      Hieroglyph.log 'polygon found - converting', 9
      points = content['points'].split(" ")
      Savage::Path.new do |path|
        start_position = points.shift.split(",")
        path.move_to(start_position[0], start_position[1])
        points.each do |point|
          position = point.split(",")
          path.line_to(position[0], position[1])
        end
        path.close_path
        flip(path)
      end
    end

    def convert_path(type, content)
      path = Savage::Parser.parse(content['d'])
      flip(path)
    end

    def report_invalid(type, content)
      Hieroglyph.error "#{type} found - this shape is invalid!", 4
      Hieroglyph.error "'make compound path' in your vector tool to fix", 4
    end

    def report_too_many
      unless @too_many
        Hieroglyph.error 'too many shapes! your icon might look weird as a result', 4
        @too_many = true
      end
    end

    def flip(path)
      path.subpaths.each do |subpath|
        subpath.directions.each do |direction|
          case direction
          when Savage::Directions::MoveTo
            if(direction.absolute?)
              direction.target.y = flip_y(direction.target.y)
            else
              direction.target.y = -1 * direction.target.y
            end
          when Savage::Directions::VerticalTo
            if(direction.absolute?)
              direction.target = flip_y(direction.target)
            else
              direction.target = -1 * direction.target
            end
          when Savage::Directions::LineTo
            if(direction.absolute?)
              direction.target.y = flip_y(direction.target.y)
            else
              direction.target.y = -1 * direction.target.y
            end
          when Savage::Directions::CubicCurveTo
            if(direction.absolute?)
              direction.control.y = flip_y(direction.control.y)
              direction.target.y = flip_y(direction.target.y)
              if(defined?(direction.control_1) && defined?(direction.control_1.y))
                direction.control_1.y = flip_y(direction.control_1.y)
              end
            else
              direction.control.y = -1 * direction.control.y
              direction.target.y = -1 * direction.target.y
              if(defined?(direction.control_1) && defined?(direction.control_1.y))
                direction.control_1.y = -1 * direction.control_1.y
              end
            end
          end
        end
      end
      path
    end

    def flip_y(value)
      value = value.to_f
      value = (value - 500) * -1 + 500
      value = value - 25
    end

    def to_node
      @path ? "<glyph unicode=\"#{@name}\" d=\"#{@path.to_command}\" />\n" : ''
    end

  end

end
