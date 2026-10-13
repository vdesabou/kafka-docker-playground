# Markdown formatting of the bashly help texts for https://kafka-docker-playground.io/ (CLI reference pages)
#
# The help texts are written for a terminal: two-column blocks aligned with spaces, which collapse into
# run-on lines in the proportional font of the website, and flags such as --tag that the website renders
# with a typographic dash. This turns them into Markdown:
#   - indented two-column blocks ("  --tag   description") become bullet lists with the term in code
#   - a short line followed by an indented block becomes a bold sub-heading
#   - flags, -X JVM options, <placeholders>, ENV_VARS and quoted "playground ..." commands become code spans,
#     and so do lines that are a shell command ("$ ...", "docker ...")
#   - other lines keep their line breaks, and "- " lines stay Markdown lists
module KdpMarkdown
  module_function

  PLACEHOLDER = '<[A-Za-z][\w.+\- ]*>(?::<[A-Za-z][\w.+\-]*>)*'

  INLINE = /
      "(?<pq>playground\s[^"]+)"
    | '(?<sq>playground\s[^']+)'
    | ['"](?<qf>--[a-z0-9][\w\-]*)['"]
    | (?<ph>#{PLACEHOLDER})
    | (?<![\w\-])--[a-z0-9][\w\-]*(?:\*|<\w+>)?
    | (?<![\w\-])-X[\w:+=*.\/\-]+
    | (?<![\w$])\$?[A-Z][A-Z0-9]*_[A-Z0-9_]*[A-Z0-9](?![\w])
  /x

  def escape(text)
    text.gsub(/[<>*]/) { |c| "\\#{c}" }
  end

  def code(text)
    "`#{text}`"
  end

  # one line of prose: code spans for the CLI tokens, Markdown escaping for the rest
  def inline(text)
    return "" if text.nil?

    out = +""
    pos = 0
    text.to_enum(:scan, INLINE).each do
      m = Regexp.last_match
      out << escape(text[pos...m.begin(0)])
      out << code(m[:pq] || m[:sq] || m[:qf] || m[0])
      pos = m.end(0)
    end
    out << escape(text[pos..-1])
  end

  def help(text)
    return "" if text.nil?

    text.rstrip.split(/\n[ \t]*\n/).map { |p| paragraph(p) }.reject(&:empty?).join("\n\n")
  end

  def indented?(line)
    line =~ /^\s{2,}\S/
  end

  def paragraph(par)
    lines = par.split("\n").map(&:rstrip)
    lines.shift while lines.first && lines.first.strip.empty?
    return "" if lines.empty?

    if lines.size > 1 && !indented?(lines[0]) && lines[1..-1].all? { |l| indented?(l) }
      # a short title over a two-column block becomes a sub-heading, otherwise it is a wrapped sentence
      if two_columns?(lines[1..-1]) && lines[0].length <= 60 && !lines[0].include?('. ')
        return "**#{inline(lines[0].strip)}**\n\n#{block(lines[1..-1])}"
      end

      return prose(lines)
    end

    lines.all? { |l| indented?(l) } ? block(lines) : prose(lines)
  end

  def two_columns?(lines)
    lines.any? { |l| l.strip =~ /\S\s{2,}\S/ }
  end

  COMMAND = /^(\$ |playground |alias |export |source |docker |curl |confluent |kubectl )/

  # lines that were indented for the terminal
  def block(lines)
    unless two_columns?(lines)
      return "```bash\n#{lines.map(&:strip).join("\n")}\n```" if lines.all? { |l| l.strip =~ COMMAND }
      return lines.map { |l| "- #{inline(l.strip.sub(/^- /, ''))}" }.join("\n") if lines.all? { |l| l.strip.start_with?('-') }

      return prose(lines)
    end

    base = lines.map { |l| l[/^\s*/].size }.min
    rows = []
    lines.each do |l|
      s = l.strip
      if l[/^\s*/].size > base + 1 && !rows.empty?
        rows.last[1] = [rows.last[1], s].reject(&:empty?).join(' ')
      elsif s =~ /^(\S.*?)\s{2,}(\S.*)$/
        rows << [Regexp.last_match(1), Regexp.last_match(2)]
      else
        rows << [s, '']
      end
    end
    rows.map { |term, desc| "- #{term(term)}#{desc.empty? ? '' : ": #{inline(desc)}"}" }.join("\n")
  end

  def term(text)
    if text =~ /^(-|playground\b|<|\$)/
      text.start_with?('-') ? text.split(/,\s*/).map { |t| code(t) }.join(', ') : code(text)
    else
      "**#{inline(text)}**"
    end
  end

  # regular lines: keep the line breaks of the terminal help, and Markdown lists
  def prose(lines)
    out = +""
    previous_list = nil
    lines.each_with_index do |l, i|
      s = l.strip
      list = s =~ /^([-*]|\d+\.) / ? true : false
      out << (previous_list != list ? "\n\n" : (list ? "\n" : "  \n")) if i > 0
      previous_list = list
      if list
        out << s.sub(/^([-*]|\d+\.) (.*)$/) { "#{Regexp.last_match(1) == '*' ? '-' : Regexp.last_match(1)} #{inline(Regexp.last_match(2))}" }
      elsif command_line?(s)
        out << code(s)
      else
        out << inline(s)
      end
    end
    out
  end

  # "$ docker exec kcat kcat -b broker:9092 -L", not "docker must be running"
  def command_line?(line)
    return false if line.include?('`')

    line.start_with?('$ ') || (line =~ COMMAND && line =~ / -|[=|<]/)
  end

  def values(list)
    Array(list).map { |v| code(v) }.join(', ')
  end
end

class String
  def for_kdp_markdown
    KdpMarkdown.help(self)
  end

  def for_kdp_inline
    KdpMarkdown.inline(self)
  end
end
