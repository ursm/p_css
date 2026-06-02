module CSS
  module Selectors
    # Matches a Selector AST against any duck-typed element. Required
    # methods on the element:
    #
    #   - `name` (or `tag_name`)            — tag name
    #   - `[](attr)`                         — attribute value or nil
    #   - `parent`                           — parent element or non-element
    #   - `previous_element` (or `previous_element_sibling`) — preceding
    #     element sibling
    #   - `next_element` (or `next_element_sibling`)         — following
    #     element sibling
    #   - `children` (and optionally `element_children`) — child nodes
    #
    # `Nokogiri::XML::Element` and `Nokogiri::HTML::Element` satisfy this
    # protocol out of the box.
    #
    # Pseudo-classes that depend on user-agent state (`:hover`, `:focus`,
    # `:visited`, etc.) return false by default; pass an explicit `state:`
    # mapping to opt into stateful matching. Validity-API and viewport-
    # only states (`:fullscreen`, `:valid`, …) are not exposed.
    module Matcher
      extend self

      DISABLEABLE_TAGS = %w[button input select textarea optgroup option fieldset].freeze
      INPUT_TAGS       = %w[input textarea select].freeze
      LINK_TAGS        = %w[a area link].freeze
      RO_INPUT_TYPES   = %w[hidden range color checkbox radio file submit image reset button].freeze

      # User-agent state pseudos. The matcher returns `false` for these
      # unless the caller passes a `state:` Hash describing which
      # elements (or "all") should match.
      STATEFUL_PSEUDOS = %w[hover focus focus-within focus-visible active visited target].to_set.freeze

      # Per spec these states propagate up the ancestor chain — if a
      # descendant is hovered/active/contains-focus, the ancestors
      # share the state for selector-matching purposes.
      PROPAGATING_STATEFUL_PSEUDOS = %w[hover active focus-within].to_set.freeze

      # Per-element cache used to avoid recomputing tag / id / class set
      # for every selector in a hot loop (e.g. `Cascade#resolve` against
      # hundreds of rules). Keyed by `Object#object_id`; only valid for
      # the duration of a single matcher invocation.
      Context = Data.define(:tag, :id, :classes)

      EMPTY_CLASSES = [].freeze

      def matches?(element, selector, cache: nil, state: nil)
        sel = selector.is_a?(String) ? Parser.parse_selector_list(selector) : selector

        case sel
        when SelectorList
          sel.selectors.any? { match_complex(element, _1, cache, state) }
        when ComplexSelector
          match_complex(element, sel, cache, state)
        when CompoundSelector
          match_compound(element, sel, cache, state)
        else
          raise ArgumentError, "expected a selector node or string, got #{sel.class}"
        end
      end

      private

      # Walks the complex selector right-to-left starting at the rightmost
      # compound. Each combinator either succeeds against ancestors /
      # siblings of the current candidate or fails the whole match.
      def match_complex(element, complex, cache, state)
        match_at(element, complex, complex.compounds.size - 1, cache, state)
      end

      def match_at(element, complex, index, cache, state)
        return false if element.nil?
        return false unless match_compound(element, complex.compounds[index], cache, state)
        return true  if index.zero?

        prev = index - 1

        case complex.combinators[prev]
        when :descendant         then walk_until_match(element, complex, prev, :parent_element,   cache, state)
        when :child              then match_at(parent_element(element), complex, prev, cache, state)
        when :next_sibling       then match_at(previous_element(element), complex, prev, cache, state)
        when :subsequent_sibling then walk_until_match(element, complex, prev, :previous_element, cache, state)
        end
      end

      # Steps along the DOM via `direction` until a candidate matches the
      # remaining complex selector or the chain runs out.
      def walk_until_match(element, complex, index, direction, cache, state)
        candidate = send(direction, element)

        while candidate
          return true if match_at(candidate, complex, index, cache, state)

          candidate = send(direction, candidate)
        end

        false
      end

      def match_compound(element, compound, cache, state)
        components = compound.components
        i          = 0
        n          = components.size

        while i < n
          return false unless match_simple(element, components[i], cache, state)

          i += 1
        end

        true
      end

      def match_simple(element, simple, cache, state)
        case simple
        when TypeSelector      then tag_of(element, cache).casecmp?(simple.name)
        when UniversalSelector then true
        when IdSelector        then id_of(element, cache) == simple.name
        when ClassSelector     then classes_of(element, cache).include?(simple.name)
        when AttributeSelector then match_attribute(element, simple)
        when PseudoClass       then match_pseudo_class(element, simple, cache, state)
        when PseudoElement     then false
        when NestingSelector   then false
        else                        false
        end
      end

      # Public — used by `Cascade` for both rule indexing and matching;
      # callers can share a `cache` Hash with `matches?(cache: cache)`
      # so each element pays for its tag / id / class set at most once.
      public

      def tag_of(element, cache = nil)
        ctx = context_for(element, cache)
        ctx ? ctx.tag : tag(element)
      end

      def id_of(element, cache = nil)
        ctx = context_for(element, cache)
        ctx ? ctx.id : attr(element, 'id')
      end

      def classes_of(element, cache = nil)
        ctx = context_for(element, cache)
        ctx ? ctx.classes : build_class_set(element)
      end

      private

      def context_for(element, cache)
        return nil if cache.nil?

        cache[element.object_id] ||= Context.new(
          tag:     tag(element),
          id:      attr(element, 'id'),
          classes: build_class_set(element)
        )
      end

      # Returns an Array of class names. We deliberately don't wrap in a Set:
      # construction allocates two objects (Array + Set), and on the typical
      # 1–5 classes per element, Array#include? is fast enough that the
      # construction win dominates the lookup penalty.
      def build_class_set(element)
        v = attr(element, 'class')
        return EMPTY_CLASSES if v.nil? || v.empty?

        v.to_s.split(' ')
      end

      # Attribute matching ----------------------------------------------

      def match_attribute(element, attr_sel)
        actual = attr(element, attr_sel.name)

        return false if actual.nil?
        return true  if attr_sel.matcher.nil?

        haystack = actual.to_s
        needle   = attr_sel.value.to_s

        if attr_sel.case_flag == :i
          haystack = haystack.downcase
          needle   = needle.downcase
        end

        case attr_sel.matcher
        when :exact     then haystack == needle
        when :includes  then !needle.empty? && haystack.split(/\s+/).include?(needle)
        when :dash      then haystack == needle || haystack.start_with?("#{needle}-")
        when :prefix    then !needle.empty? && haystack.start_with?(needle)
        when :suffix    then !needle.empty? && haystack.end_with?(needle)
        when :substring then !needle.empty? && haystack.include?(needle)
        end
      end

      # Pseudo-class matching -------------------------------------------

      def match_pseudo_class(element, pc, cache, state)
        name = pc.name.downcase

        return match_stateful_pseudo?(name, element, state) if STATEFUL_PSEUDOS.include?(name)

        case name
        when 'is', 'where', 'matches'   then match_selector_list_arg(element, pc.argument, cache, state)
        when 'not'                       then negate_selector_list_arg(element, pc.argument, cache, state)
        when 'has'                       then false
        when 'root'                      then parent_element(element).nil?
        when 'scope'                     then parent_element(element).nil?
        when 'first-child'               then previous_element(element).nil?
        when 'last-child'                then next_element(element).nil?
        when 'only-child'                then previous_element(element).nil? && next_element(element).nil?
        when 'first-of-type'             then same_type_previous(element).nil?
        when 'last-of-type'              then same_type_next(element).nil?
        when 'only-of-type'              then same_type_previous(element).nil? && same_type_next(element).nil?
        when 'nth-child'                 then match_nth(element, pc.argument, of_type: false, from_end: false)
        when 'nth-last-child'            then match_nth(element, pc.argument, of_type: false, from_end: true)
        when 'nth-of-type'               then match_nth(element, pc.argument, of_type: true,  from_end: false)
        when 'nth-last-of-type'          then match_nth(element, pc.argument, of_type: true,  from_end: true)
        when 'empty'                     then empty?(element)
        when 'link', 'any-link'          then link?(element)
        when 'enabled'                   then disableable?(element) && !disabled?(element)
        when 'disabled'                  then disabled?(element)
        when 'checked'                   then checked?(element)
        when 'required'                  then required?(element)
        when 'optional'                  then optional?(element)
        when 'read-only'                 then read_only?(element)
        when 'read-write'                then read_write?(element)
        when 'placeholder-shown'         then placeholder_shown?(element)
        when 'lang'                      then match_lang(element, pc.argument)
        when 'dir'                       then match_dir(element, pc.argument)
        when 'defined'                   then true
        else                                  false
        end
      end

      # `:hover` / `:active` / `:focus-within` propagate up the ancestor
      # chain per Selectors §10 — the Set members are the *source* nodes
      # (e.g. the deepest hovered element) and any of their ancestors
      # also matches. Other stateful pseudos match only the explicit
      # elements in the Set.
      def match_stateful_pseudo?(name, element, state)
        return false if state.nil?

        value = state[name.to_sym] || state[name]

        return false   if value.nil? || value == false
        return true    if value == true

        return value.include?(element) unless PROPAGATING_STATEFUL_PSEUDOS.include?(name)

        value.each do |source|
          cur = source

          while cur
            return true if cur == element

            cur = parent_element(cur)
          end
        end

        false
      end

      def match_selector_list_arg(element, arg, cache, state)
        arg.is_a?(SelectorList) && matches?(element, arg, cache: cache, state: state)
      end

      def negate_selector_list_arg(element, arg, cache, state)
        arg.is_a?(SelectorList) && !matches?(element, arg, cache: cache, state: state)
      end

      def match_nth(element, anb, of_type:, from_end:)
        return false unless anb.is_a?(AnB)

        index = nth_index(element, of_type:, from_end:)

        return false if index.nil?

        step   = anb.step
        offset = anb.offset

        if step.zero?
          index == offset
        else
          diff = index - offset
          (diff % step).zero? && (diff / step) >= 0
        end
      end

      def nth_index(element, of_type:, from_end:)
        p = parent_element(element)

        return nil if p.nil?

        siblings = element_children(p)

        if of_type
          own_tag  = tag(element)
          siblings = siblings.select { tag(_1) == own_tag }
        end

        siblings = siblings.reverse if from_end

        idx = siblings.index { same_node?(_1, element) }
        idx && idx + 1
      end

      # Form / link state -----------------------------------------------

      def link?(element)
        LINK_TAGS.include?(tag(element)) && !attr(element, 'href').nil?
      end

      def disableable?(element)
        DISABLEABLE_TAGS.include?(tag(element))
      end

      def disabled?(element)
        return false unless disableable?(element)
        return true  if attr(element, 'disabled')

        ancestor = parent_element(element)

        while ancestor
          if tag(ancestor) == 'fieldset' && attr(ancestor, 'disabled')
            return true unless inside_first_legend?(element, ancestor)
          end

          ancestor = parent_element(ancestor)
        end

        false
      end

      def inside_first_legend?(element, fieldset)
        first_legend = element_children(fieldset).find { tag(_1) == 'legend' }

        return false if first_legend.nil?

        ancestor = element

        while ancestor
          return true if same_node?(ancestor, first_legend)
          break       if same_node?(ancestor, fieldset)

          ancestor = parent_element(ancestor)
        end

        false
      end

      def checked?(element)
        case tag(element)
        when 'input'
          %w[checkbox radio].include?(attr(element, 'type').to_s.downcase) && !attr(element, 'checked').nil?
        when 'option'
          !attr(element, 'selected').nil?
        else
          false
        end
      end

      def required?(element)
        INPUT_TAGS.include?(tag(element)) && !attr(element, 'required').nil?
      end

      def optional?(element)
        INPUT_TAGS.include?(tag(element)) && attr(element, 'required').nil?
      end

      def read_only?(element)
        case tag(element)
        when 'input'
          type = attr(element, 'type').to_s.downcase
          return true if RO_INPUT_TYPES.include?(type)

          !attr(element, 'readonly').nil? || disabled?(element)
        when 'textarea'
          !attr(element, 'readonly').nil? || disabled?(element)
        else
          ce = attr(element, 'contenteditable').to_s.downcase
          ce.empty? || (ce != 'true' && ce != 'plaintext-only')
        end
      end

      def read_write?(element)
        return !read_only?(element) if %w[input textarea].include?(tag(element))

        ce = attr(element, 'contenteditable').to_s.downcase
        ce == 'true' || ce == 'plaintext-only'
      end

      def placeholder_shown?(element)
        return false unless %w[input textarea].include?(tag(element))
        return false if attr(element, 'placeholder').nil?

        v = attr(element, 'value')
        v.nil? || v.empty?
      end

      def match_lang(element, argument)
        target = ident_argument(argument)

        return false if target.nil?

        target = target.downcase
        ancestor = element

        while ancestor
          actual = attr(ancestor, 'lang') || attr(ancestor, 'xml:lang')

          if actual
            actual = actual.to_s.downcase
            return actual == target || actual.start_with?("#{target}-")
          end

          ancestor = parent_element(ancestor)
        end

        false
      end

      def match_dir(element, argument)
        target = ident_argument(argument)

        return false if target.nil?

        target = target.downcase
        ancestor = element

        while ancestor
          actual = attr(ancestor, 'dir')

          if actual
            return actual.to_s.downcase == target
          end

          ancestor = parent_element(ancestor)
        end

        target == 'ltr'
      end

      def ident_argument(argument)
        return nil unless argument.is_a?(Array)

        token = argument.find { _1.is_a?(Token) && (_1.type == :ident || _1.type == :string) }
        token&.value
      end

      # CSS3 :empty semantics — element children always disqualify;
      # whitespace-only text content does not. Comments / PIs / doctypes
      # are ignored.
      def empty?(element)
        return false unless element.respond_to?(:children)

        element.children.each do |child|
          if child.respond_to?(:element?) && child.element?
            return false
          end

          if child.respond_to?(:text?) && child.text?
            content = child.respond_to?(:content) ? child.content : child.text
            return false if content.to_s.match?(/\S/)
          end
        end

        true
      end

      # Element protocol helpers ---------------------------------------

      # Callers (LINK_TAGS.include?, case statements) compare against
      # lowercase literals, so the result must be lowercase. But Nokogiri's
      # HTML parsers already emit lowercase names — the .downcase only fires
      # in XML / uppercase-tag cases. Skip the allocation when there's
      # nothing to lower.
      def tag(element)
        name = element.respond_to?(:tag_name) ? element.tag_name : element.name
        name = name.to_s
        name.match?(/[A-Z]/) ? name.downcase : name
      end

      def attr(element, name)
        v = element[name]
        return v unless v.nil?

        lower = name.downcase
        return nil if name == lower

        element[lower]
      end

      def parent_element(element)
        p = element.respond_to?(:parent) ? element.parent : nil

        return nil if p.nil?
        return nil if p.respond_to?(:element?) && !p.element?

        p
      end

      SIBLING_METHODS = {
        previous: %i[previous_element previous_element_sibling previous_sibling],
        next:     %i[next_element     next_element_sibling     next_sibling]
      }.freeze

      def previous_element(element) = adjacent_element(element, :previous)
      def next_element(element)     = adjacent_element(element, :next)

      def adjacent_element(element, direction)
        primary, alt, fallback = SIBLING_METHODS.fetch(direction)

        return element.send(primary) if element.respond_to?(primary)
        return element.send(alt)     if element.respond_to?(alt)

        walk_sibling(element, fallback)
      end

      def walk_sibling(element, direction)
        sib = element.respond_to?(direction) ? element.send(direction) : nil

        until sib.nil?
          return sib if !sib.respond_to?(:element?) || sib.element?

          sib = sib.respond_to?(direction) ? sib.send(direction) : nil
        end

        nil
      end

      def element_children(element)
        return element.element_children.to_a if element.respond_to?(:element_children)
        return [] unless element.respond_to?(:children)

        element.children.select {|c|
          c.respond_to?(:element?) ? c.element? : false
        }
      end

      def same_type_previous(element)
        sib = previous_element(element)
        sib = previous_element(sib) until sib.nil? || tag(sib).casecmp?(tag(element))
        sib
      end

      def same_type_next(element)
        sib = next_element(element)
        sib = next_element(sib) until sib.nil? || tag(sib).casecmp?(tag(element))
        sib
      end

      def same_node?(a, b)
        a.equal?(b) || a == b
      end
    end
  end
end
