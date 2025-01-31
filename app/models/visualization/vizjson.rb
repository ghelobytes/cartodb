# encoding: utf-8
require 'json'
require 'ostruct'
require_relative '../overlay/presenter'
require_relative '../layer/presenter'
require_relative '../layer_group/presenter'
require_relative '../named_map/presenter'
require_relative '../../../services/named-maps-api-wrapper/lib/named_maps_wrapper'


module CartoDB
  module Visualization
    class VizJSON
      VIZJSON_VERSION     = '0.1.0'

      def initialize(visualization, options={}, configuration={}, logger=nil)
        @visualization    = visualization
        @map              = visualization.map
        @options          = default_options.merge(options)
        @configuration    = configuration
        @user             = options.fetch(:user, nil)
        logger.info(map.inspect) if logger
      end

      # Return a PORO (Hash object) for easy JSONification
      # @see https://github.com/CartoDB/cartodb.js/blob/privacy-maps/doc/vizjson_format.md
      def to_poro
        poro_data = {
          id:             visualization.id,
          version:        VIZJSON_VERSION,
          title:          visualization.qualified_name(@user),
          likes:          visualization.likes.count,
          description:    visualization.description_html_safe,
          scrollwheel:    map.scrollwheel,
          legends:        map.legends,
          url:            options.delete(:url),
          map_provider:   map.provider,
          bounds:         bounds_from(map),
          center:         map.center,
          zoom:           map.zoom,
          updated_at:     map.viz_updated_at,
          layers:         layers_for(visualization),
          overlays:       overlays_for(visualization),
          prev:           visualization.prev_id,
          next:           visualization.next_id,
          transition_options: visualization.transition_options
        }

        auth_tokens = auth_tokens_for(visualization)
        poro_data.merge!({auth_tokens: auth_tokens}) if auth_tokens.length > 0

        children = children_for(visualization)
        poro_data.merge!({slides: children}) if children.length > 0
        unless visualization.parent_id.nil?
          poro_data[:title] = visualization.parent.qualified_name(@user)
          poro_data[:description] = visualization.parent.description_html_safe
        end

        poro_data
      end

      def layer_group_for(visualization)
        LayerGroup::Presenter.new(visualization.layers(:cartodb), options, configuration).to_poro
      end

      def named_map_layer_group_for(visualization)
        LayerGroup::Presenter.new(visualization.layers(:named_map), options, configuration).to_poro
      end

      def other_layers_for(visualization, named_maps_presenter = nil)
        layer_index = visualization.layers(:cartodb).size

        visualization.layers(:others).map do |layer|
          if named_maps_presenter.nil?
            decoration_data_to_apply = {}
          else
            decoration_data_to_apply = named_maps_presenter.get_decoration_for_layer(layer.kind, layer_index)
          end
          layer_index += 1
          CartoDB::Layer::Presenter.new(layer, options, configuration, decoration_data_to_apply).to_vizjson_v2
        end
      end

      private

      attr_reader :visualization, :map, :options, :configuration

      def bounds_from(map)
        ::JSON.parse("[#{map.view_bounds_sw}, #{map.view_bounds_ne}]")
      rescue
        # Do nothing
      end

      def layers_for(visualization)
        basemap_layer = basemap_layer_for(visualization)
        layers_data = []
        layers_data.push(basemap_layer) if basemap_layer

        if visualization.retrieve_named_map?
          presenter_options = {
            user_name: options.fetch(:user_name),
            api_key: options.delete(:user_api_key),
            https_request: options.fetch(:https_request, false),
            viewer_user: @user,
            owner: visualization.user
          }
          named_maps_presenter = CartoDB::NamedMapsWrapper::Presenter.new(
            visualization, layer_group_for_named_map(visualization), presenter_options, configuration
          )
          layers_data.push(named_maps_presenter.to_poro)
        else
          named_maps_presenter = nil
          layers_data.push(layer_group_for(visualization))
        end
        layers_data.push(other_layers_for(visualization, named_maps_presenter))

        layers_data += non_basemap_base_layers_for(visualization)

        layers_data.compact.flatten
      end

      def layer_group_for_named_map(visualization)
        layer_group_poro = layer_group_for(visualization)
        # If there is *only* a torque layer, there is no layergroup
        return {} if layer_group_poro.nil?

        layers_data = Array.new
        layer_num = 0
        layer_group_poro[:options][:layer_definition][:layers].each { |layer|
          layers_data.push( {
                              type:       layer[:type],
                              options:    layer[:options],
                              visible:    layer[:visible],
                              index:      layer_num
                            } )
          layer_num += 1
        }
        layers_data
      end

      # INFO: Assumes layers come always ordered by order (they do)
      def basemap_layer_for(visualization)
        layer = visualization.layers(:base).first
        CartoDB::Layer::Presenter.new(layer, options, configuration).to_vizjson_v2 unless layer.nil?
      end

      # INFO: Assumes layers come always ordered by order (they do)
      def non_basemap_base_layers_for(visualization)
        base_layers = visualization.layers(:base)
        if base_layers.length > 0
          # Remove the basemap, which is always first
          base_layers.slice(1, visualization.layers(:base).length)
                     .map do |layer|
            CartoDB::Layer::Presenter.new(layer, options, configuration).to_vizjson_v2
          end
        else
          []
        end
      end

      def overlays_for(visualization)
        ordered_overlays_for(visualization).map do |overlay|
          Overlay::Presenter.new(overlay).to_poro
        end
      end

      def children_for(visualization)
        visualization.children.map do |vis|
          vis.to_vizjson
        end
      end

      def ordered_overlays_for(visualization)
        visualization.overlays.to_a
      end

      def default_options
        { full: true, visualization_id: visualization.id, https_request: false }
      end

      def auth_tokens_for(visualization)
        visualization.has_password? ? visualization.get_auth_tokens : []
      end

    end
  end
end
