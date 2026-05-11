require_relative '../css'
require_relative 'css_native'

module CSS
  module Native
    # High-level wrapper: takes a Nokogiri element + a selector (string or
    # parsed AST) and returns matches?(element). Falls back to the pure-Ruby
    # Matcher when the selector contains features the native matcher doesn't
    # support yet (pseudo-classes, :not, etc.).
    #
    # `document:` / `snapshot:` let callers control snapshot reuse across
    # many matches against the same DOM. With neither, a per-document
    # snapshot is cached by document identity.
    class << self
      def matches?(element, selector, snapshot: nil, document: nil)
        ast      = selector.is_a?(String) ? CSS.parse_selector_list(selector) : selector
        compiled = compile_or_nil(ast)

        return CSS.matches?(element, ast) unless compiled

        snap = snapshot || snapshot_for(document || element.document)
        snap.matches?(element, compiled)
      end

      private

      def compile_or_nil(ast)
        Selector.compile(ast)
      rescue Unsupported
        nil
      end

      def snapshot_for(document)
        (@snapshots ||= {}.compare_by_identity)[document] ||= Snapshot.from_document(document)
      end
    end
  end
end
