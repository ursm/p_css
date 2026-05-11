require_relative '../css'

# cibuildgem ships precompiled binaries at lib/css/<ruby_minor>/css_native.{so,bundle,dll}.
# When users compile the gem from source (no platform gem available),
# extconf.rb places the binary at lib/css/css_native.{so,bundle,dll}.
# Try the version-specific path first, fall back to the non-versioned one.
begin
  ruby_minor = RUBY_VERSION[/\d+\.\d+/]
  require "css/#{ruby_minor}/css_native"
rescue LoadError
  require_relative 'css_native'
end

# Rust defines matches?, matches_any?, match_indices with a required
# `state` argument (3 args). Wrap them in Ruby so callers can pass 2
# args when stateful pseudos aren't relevant.
module CSS
  module Native
    class Snapshot
      alias_method :_native_matches?,      :matches?
      alias_method :_native_matches_any?,  :matches_any?
      alias_method :_native_match_indices, :match_indices

      def matches?(element, selector, state = nil)
        _native_matches?(element, selector, state)
      end

      def matches_any?(element, selectors, state = nil)
        _native_matches_any?(element, selectors, state)
      end

      def match_indices(element, selectors, state = nil)
        _native_match_indices(element, selectors, state)
      end
    end
  end
end

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
      def matches?(element, selector, snapshot: nil, document: nil, state: nil)
        ast      = selector.is_a?(String) ? CSS.parse_selector_list(selector) : selector
        compiled = compile_or_nil(ast)
        snap     = snapshot || snapshot_for(document || element.document)

        return CSS.matches?(element, ast, state: state) unless compiled

        native_state = state.nil? ? nil : (state.is_a?(State) ? state : snap.compile_state(state))
        snap.matches?(element, compiled, native_state)
      end

      def compile_or_nil(ast)
        Selector.compile(ast)
      rescue Unsupported
        nil
      end

      private

      def snapshot_for(document)
        (@snapshots ||= {}.compare_by_identity)[document] ||= Snapshot.from_document(document)
      end
    end

    # Subclass of CSS::Cascade that uses the native matcher for the inner
    # rule-matching loop. Selectors are pre-compiled at construction —
    # those that can't be compiled (pseudo-classes etc.) fall through to
    # the pure-Ruby matcher, so behavior is identical to CSS::Cascade.
    #
    # Requires a Nokogiri document at construction; the snapshot is built
    # once and reused for every resolve(). Mutate the DOM and you must
    # construct a fresh CSS::Native::Cascade.
    class Cascade < CSS::Cascade
      def initialize(stylesheet, document, context: CSS::MediaQueries::Context.default)
        super(stylesheet, context: context)

        @snapshot        = Snapshot.from_document(document)
        @compiled_by_ast = {}.compare_by_identity

        @entries.each do |entry|
          entry.selector_pairs.each {|ast, _spec|
            @compiled_by_ast[ast] = Native.compile_or_nil(ast)
          }
        end
      end

      # Override: batch every candidate's compiled selectors into one FFI
      # hop per resolve (GVL released), then merge in any Ruby-fallback
      # matches. Cuts per-resolve FFI cost from O(candidates) to O(1).
      def resolve(element, inline_style: nil, state: nil)
        cache        = {}
        candidates   = collect_candidate_indexes(element, cache)
        order        = 0
        matches      = []
        native_state = state && @snapshot.compile_state(state)

        best_by_entry = native_pass(element, candidates, native_state)
        ruby_fallback_pass(element, candidates, best_by_entry, cache, state)

        candidates.each do |entry_idx|
          spec = best_by_entry[entry_idx] or next

          @entries[entry_idx].declarations.each {|decl|
            order += 1
            matches << CSS::Cascade::Match.new(declaration: decl, specificity: spec, inline: false, order: order)
          }
        end

        if inline_style
          inline_declarations(inline_style).each {|decl|
            order += 1
            matches << CSS::Cascade::Match.new(
              declaration: decl,
              specificity: CSS::Selectors::Specificity::ZERO,
              inline:      true,
              order:       order
            )
          }
        end

        pick_winners(matches)
      end

      private

      # Flatten the candidates' compiled selectors into one batched
      # match_indices call. Returns Hash{entry_idx => best_specificity}.
      def native_pass(element, candidates, native_state)
        positions = []
        sels      = []

        candidates.each do |entry_idx|
          @entries[entry_idx].selector_pairs.each {|ast, spec|
            compiled = @compiled_by_ast[ast] or next

            positions << [entry_idx, spec]
            sels      << compiled
          }
        end

        best_by_entry = {}

        return best_by_entry if sels.empty?

        @snapshot.match_indices(element, sels, native_state).each {|i|
          entry_idx, spec = positions[i]
          cur             = best_by_entry[entry_idx]

          best_by_entry[entry_idx] = spec if cur.nil? || spec > cur
        }

        best_by_entry
      end

      # Run pure-Ruby matching for any selectors that didn't compile
      # (pseudo-classes, etc.), merging results into best_by_entry.
      def ruby_fallback_pass(element, candidates, best_by_entry, cache, state)
        candidates.each do |entry_idx|
          @entries[entry_idx].selector_pairs.each {|ast, spec|
            next if @compiled_by_ast[ast]
            next unless Selectors::Matcher.matches?(element, ast, cache: cache, state: state)

            cur = best_by_entry[entry_idx]
            best_by_entry[entry_idx] = spec if cur.nil? || spec > cur
          }
        end
      end
    end
  end
end
