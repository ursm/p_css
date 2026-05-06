module CSS
  # CSS Syntax §9.3 escape primitives — `serialize an identifier`,
  # `serialize a name`, and `serialize a string`. Reused by both the main
  # serializer and the selector serializer.
  module Escape
    extend self
    extend CodePoints

    # §9.3.1.
    def ident(ident)
      buf       = +''
      lone_dash = ident.length == 1 && ident == '-'
      hyphen0   = ident.start_with?('-')

      ident.each_char.with_index {|c, i|
        cp = c.ord

        if (esc = control_or_nul(cp))
          buf << esc
        elsif i.zero? && lone_dash
          buf << '\\-'
        elsif (i.zero? && digit?(c)) || (i == 1 && hyphen0 && digit?(c))
          buf << format('\\%x ', cp)
        elsif ident_code_point?(c)
          buf << c
        else
          buf << "\\#{c}"
        end
      }

      buf
    end

    # §9.3 "Serialize a name". Like an ident but allows leading digits
    # and hyphens — used for unrestricted hash tokens.
    def name(name)
      buf = +''

      name.each_char {|c|
        cp = c.ord

        if (esc = control_or_nul(cp))
          buf << esc
        elsif ident_code_point?(c)
          buf << c
        else
          buf << "\\#{c}"
        end
      }

      buf
    end

    # §9.3.2. Always uses double quotes.
    def string(s)
      buf = +'"'

      s.each_char {|c|
        cp = c.ord

        if (esc = control_or_nul(cp))
          buf << esc
        elsif c == '"' || c == '\\'
          buf << "\\#{c}"
        else
          buf << c
        end
      }

      buf << '"'
    end

    # NUL collapses to U+FFFD; controls (0x01..0x1F, 0x7F) get hex
    # escapes. Returns nil for non-control code points.
    def control_or_nul(cp)
      return CodePoints::REPLACEMENT if cp.zero?
      return format('\\%x ', cp)     if (0x01..0x1F).cover?(cp) || cp == 0x7F

      nil
    end
  end
end
