module CSS
  module MediaQueries
    # Holds the user-agent context against which a MediaQueryList is
    # evaluated. Stored as a feature → value Hash; values follow Media
    # Queries Level 4 conventions:
    #
    #   - lengths in CSS pixels (Numeric)
    #   - resolution in dots-per-CSS-px (`dppx`, Numeric)
    #   - identifier-valued features as Strings ("landscape", "dark", ...)
    #   - boolean-style features as 1 / 0 or true / false
    #
    # `Context.default(**overrides)` returns a sensible desktop preset.
    Context = Data.define(:features) do
      def [](name) = features[name.to_s]

      def media_type = self['media-type']

      def with(**overrides)
        Context.new(features: features.merge(overrides.transform_keys(&:to_s)))
      end

      def self.default(**overrides)
        new(features: DEFAULTS.merge(overrides.transform_keys(&:to_s)))
      end

      DEFAULTS = {
        'media-type'             => 'screen',
        'width'                  => 1024,
        'height'                 => 768,
        'device-width'           => 1024,
        'device-height'          => 768,
        'resolution'             => 1,    # dppx
        'orientation'            => 'landscape',
        'aspect-ratio'           => 1024.0 / 768,
        'device-aspect-ratio'    => 1024.0 / 768,
        'color'                  => 8,
        'color-gamut'            => 'srgb',
        'color-index'            => 0,
        'monochrome'             => 0,
        'grid'                   => 0,
        'scan'                   => 'progressive',
        'update'                 => 'fast',
        'overflow-block'         => 'scroll',
        'overflow-inline'        => 'scroll',
        'pointer'                => 'fine',
        'hover'                  => 'hover',
        'any-pointer'            => 'fine',
        'any-hover'              => 'hover',
        'prefers-color-scheme'   => 'light',
        'prefers-reduced-motion' => 'no-preference',
        'prefers-contrast'       => 'no-preference',
        'forced-colors'          => 'none'
      }.freeze
    end
  end
end
