# coding: UTF-8
require_relative '../../../models/visualization/presenter'
require_relative '../../../../services/named-maps-api-wrapper/lib/named-maps-wrapper/exceptions'

class Api::Json::TablesController < Api::ApplicationController
  TABLE_QUOTA_REACHED_TEXT = 'You have reached your table quota'

  ssl_required :show, :create, :update, :destroy

  before_filter :load_table, except: [:create]
  before_filter :set_start_time

  # Very basic controller method to simply make blank tables
  # All other table creation things are controlled via the imports_controller#create
  def create
    @stats_aggregator.timing('tables.create') do

      begin
        @table = ::Table.new
        @table.user_id = current_user.id
        if params[:name]
          @table.name = params[:name]
        else
          @table.name = ::Table.get_valid_table_name('', {
              connection:       current_user.in_database,
              database_schema:  current_user.database_schema
          })
        end
        @table.description    = params[:description]   if params[:description]
        @table.the_geom_type  = params[:the_geom_type] if params[:the_geom_type]
        @table.force_schema   = params[:schema]        if params[:schema]
        @table.tags           = params[:tags]          if params[:tags]
        @table.import_from_query = params[:from_query]  if params[:from_query]

        save_status = @stats_aggregator.timing('save') do
          @table.valid? && @table.save
        end
          
        if save_status
          render_jsonp(@table.public_values({request:request}), 200, { location: "/tables/#{@table.id}" })
        else
          CartoDB::Logger.info 'Error on tables#create', @table.errors.full_messages
          render_jsonp( { :description => @table.errors.full_messages,
                          :stack => @table.errors.full_messages
                        }, 400)
        end
      rescue CartoDB::QuotaExceeded
        render_jsonp({ errors: [TABLE_QUOTA_REACHED_TEXT]}, 400)
      end

    end
  end

  def show
    return head(404) if @table == nil
    return head(403) unless @table.table_visualization.has_permission?(current_user, CartoDB::Visualization::Member::PERMISSION_READONLY)
    render_jsonp(@table.public_values({request:request}, current_user).merge(schema: @table.schema(reload: true)))
  end

  def update
    @stats_aggregator.timing('tables.update') do

      begin
        return head(404) if @table == nil
        return head(403) unless @table.table_visualization.has_permission?(current_user, CartoDB::Visualization::Member::PERMISSION_READWRITE)
        warnings = []

        # Perform name validations
        # TODO move this to the model!
        # TODO consider removing this code. The entry point is only used to set lat/long columns
        unless params[:name].nil?
          if params[:name].downcase != @table.name
            owner = User.select(:id,:database_name,:crypted_password,:quota_in_bytes,:username, :private_tables_enabled, :table_quota).filter(:id => current_user.id).first
            # TODO reverse this logic: make explicit if this needs to start with a letter
            if params[:name] =~ /\A[0-9_]/
              raise "Table names can't start with numbers or dashes."
            elsif owner.tables.filter(:name.like(/\A#{params[:name]}/)).select_map(:name).include?(params[:name].downcase)
              raise "Table '#{params[:name].downcase}' already exists."
            else
              @table.set_all(:name => params[:name].downcase)
              @stats_aggregator.timing('save-name') do
                @table.save(:name)
              end
            end
          end
        end

        @table.set_except(params, :name) #TODO: this is bad, passing all params blindly to the table object
        if params.keys.include?('latitude_column') && params.keys.include?('longitude_column')
          latitude_column  = params[:latitude_column]  == 'nil' ? nil : params[:latitude_column].try(:to_sym)
          longitude_column = params[:longitude_column] == 'nil' ? nil : params[:longitude_column].try(:to_sym)
          @stats_aggregator.timing('georeference') do
            @table.georeference_from!(:latitude_column => latitude_column, :longitude_column => longitude_column)
          end
          render_jsonp(@table.public_values({request:request}).merge(warnings: warnings)) and return
        end

        update_status = @stats_aggregator.timing('save') do
          @table.update(@table.values.delete_if {|k,v| k == :tags_names})
        end

        if update_status != false
          render_jsonp(@table.public_values({request:request}).merge(warnings: warnings))
        else
          render_jsonp({ :errors => @table.errors.full_messages}, 400)
        end
      rescue => e
        CartoDB::Logger.info e.class.name, e.message
        render_jsonp({ :errors => [translate_error(e.message.split("\n").first)] }, 400) and return
      rescue CartoDB::NamedMapsWrapper::HTTPResponseError => exception
        CartoDB::Logger.info "Communication error with tiler API. HTTP Code: #{exception.message}", exception.template_data
        render_jsonp({ errors: { named_maps_api: "Communication error with tiler API. HTTP Code: #{exception.message}" } }, 400)
      rescue CartoDB::NamedMapsWrapper::NamedMapDataError => exception
        render_jsonp({ errors: { named_map: exception } }, 400)
      rescue CartoDB::NamedMapsWrapper::NamedMapsDataError => exception
        render_jsonp({ errors: { named_maps: exception } }, 400)
      end

    end
  end

  def destroy
    @stats_aggregator.timing('tables.destroy') do

      begin
        @stats_aggregator.timing('ownership-check') do
          return head(403) unless @table.table_visualization.is_owner?(current_user)
        end
        @stats_aggregator.timing('delete') do
          @table.destroy
        end
        head :no_content
      rescue CartoDB::NamedMapsWrapper::HTTPResponseError => exception
        CartoDB::Logger.info "Communication error with tiler API. HTTP Code: #{exception.message}", exception.template_data
        render_jsonp({ errors: { named_maps_api: "Communication error with tiler API. HTTP Code: #{exception.message}" } }, 400)
      rescue CartoDB::NamedMapsWrapper::NamedMapDataError => exception
        render_jsonp({ errors: { named_map: exception } }, 400)
      rescue CartoDB::NamedMapsWrapper::NamedMapsDataError => exception
        render_jsonp({ errors: { named_maps: exception } }, 400)
      end
      
    end
  end

  protected

  def load_table
    @table = Helpers::TableLocator.new.get_by_id_or_name(params.fetch('id'), current_user)
  end

end
