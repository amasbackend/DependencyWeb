# Shallow split of one Ruby source file into its methods — name, visibility,
# body text and the route comment directly above it (e.g. `# GET /orders/:id`,
# the convention this app's target repos use above controller actions). Not a
# parser: good enough to answer "which method's body mentions X", which is all
# ScreenCatalog/ScreenImpactLocator need.
class RubySourceMethods
  Definition = Struct.new(:name, :private, :body, :route_comment, keyword_init: true)

  DEF_LINE = /\A\s*def\s+(?:self\.)?(?<name>[a-z_][a-zA-Z0-9_]*[?!=]?)/
  VISIBILITY_LINE = /\A\s*(?<keyword>private|protected|public)\s*(?:#.*)?\z/
  ROUTE_COMMENT = %r{\A\s*#\s*(?:GET|POST|PATCH|PUT|DELETE)\s+(?<path>/\S*)}

  def self.call(source)
    new(source).call
  end

  def initialize(source)
    @lines = source.to_s.lines
  end

  def call
    methods = []
    private_section = false
    pending_route = nil

    @lines.each do |line|
      if (visibility = VISIBILITY_LINE.match(line))
        private_section = visibility[:keyword] != "public"
      elsif (route = ROUTE_COMMENT.match(line))
        pending_route = route[:path]
      elsif (definition = DEF_LINE.match(line))
        methods << Definition.new(name: definition[:name], private: private_section, body: +"", route_comment: pending_route)
        pending_route = nil
        next
      elsif !line.strip.start_with?("#")
        pending_route = nil unless line.strip.empty?
      end

      methods.last.body << line if methods.any?
    end

    methods
  end
end
