var cdb = require('cartodb.js');
var BaseDialog = require('../views/base_dialog/view');
var pluralizeString = require('../view_helpers/pluralize_string');
var randomQuote = require('../view_helpers/random_quote');
var MapCardPreview = require('../views/mapcard_preview');
var $ = require('jquery');
var moment = require('moment');

var AFFECTED_ENTITIES_SAMPLE_COUNT = 3;
var AFFECTED_VIS_COUNT = 3;

/**
 * Delete items dialog
 */
module.exports = BaseDialog.extend({

  initialize: function() {
    this.elder('initialize');
    if (!this.options.viewModel) {
      throw new TypeError('viewModel is required');
    }
    if (!this.options.user) {
      throw new TypeError('user is required');
    }

    this._viewModel = this.options.viewModel;
    this._viewModel.loadPrerequisites();
    this._viewModel.bind('change', function() {
      if (this._viewModel.state() === 'DeleteItemsDone') {
        this.close();
      } else {
        this.render();
      }
    }, this);
    this.add_related_model(this._viewModel);
  },

  render: function() {
    BaseDialog.prototype.render.call(this);
    this._loadMapPreviews();
    return this;
  },

  /**
   * @implements cdb.ui.common.Dialog.prototype.render_content
   */
  render_content: function() {
    return this['_render' + this._viewModel.state()]();
  },

  _renderLoadingPrerequisites: function() {
    return cdb.templates.getTemplate('common/templates/loading')({
      title: 'Checking what consequences deleting the selected ' + this._pluralizedContentType() + ' would have...',
      quote: randomQuote()
    });
  },

  _renderLoadPrerequisitesFail: function() {
    return cdb.templates.getTemplate('common/templates/fail')({
      msg: 'Failed to check consequences of deleting the selected ' + this._pluralizedContentType()
    });
  },

  _renderConfirmDeletion: function() {
    // An entity can be an User or Organization
    var affectedEntities = this._viewModel.affectedEntities();
    var affectedVisData = this._viewModel.affectedVisData();

    return cdb.templates.getTemplate('common/dialogs/delete_items_view_template')({
      firstItemName: this._getFirstItemName(),
      selectedCount: this._viewModel.length,
      isDatasets: this._viewModel.isDeletingDatasets(),
      pluralizedContentType: this._pluralizedContentType(),
      affectedEntitiesCount: affectedEntities.length,
      affectedEntitiesSample: affectedEntities.slice(0, AFFECTED_ENTITIES_SAMPLE_COUNT),
      affectedEntitiesSampleCount: AFFECTED_ENTITIES_SAMPLE_COUNT,
      affectedVisCount: affectedVisData.length,
      pluralizedMaps: pluralizeString('map', affectedVisData.length),
      affectedVisVisibleCount: AFFECTED_VIS_COUNT,
      visibleAffectedVis: this._prepareVisibleAffectedVisForTemplate(affectedVisData.slice(0, AFFECTED_VIS_COUNT))
    });
  },

  _prepareVisibleAffectedVisForTemplate: function(visibleAffectedVisData) {
    return visibleAffectedVisData.map(function(visData) {
      var vis = new cdb.admin.Visualization(visData);
      var isOwner = vis.permission.isOwner(this.options.user);
      return {
        vizjson: vis.vizjsonURL(),
        name: vis.get('name'),
        url: vis.viewUrl().edit(),
        owner: vis.permission.owner,
        isOwner: isOwner,
        showPermissionIndicator: !isOwner && vis.permission.getPermission(this.options.user) === cdb.admin.Permission.READ_ONLY,
        timeDiff: moment(vis.get('updated_at')).fromNow()
      };
    }, this);
  },

  /**
   * @overrides BaseDialog.prototype.ok
   */
  ok: function() {
    this._viewModel.deleteItems();
    this.render();
  },

  _loadMapPreviews: function() {

    var self = this;

    this.$el.find('.MapCard').each(function() {
      var mapCardPreview = new MapCardPreview({
        el: $(this).find('.js-header'),
        vizjson: $(this).data('vizjson-url'),
        width: 298,
        height: 130
      }).load();

      self.addView(mapCardPreview);
    });

  },

  _renderDeletingItems: function() {
    return cdb.templates.getTemplate('common/templates/loading')({
      title: 'Deleting the selected ' + this._pluralizedContentType() + '...',
      quote: randomQuote()
    });
  },

  _renderDeleteItemsFail: function() {
    return cdb.templates.getTemplate('common/templates/fail')({
      msg: 'Failed to delete the selected ' + this._pluralizedContentType()
    });
  },

  _pluralizedContentType: function() {
    return pluralizeString(
      this._viewModel.isDeletingDatasets() ? 'dataset' : 'map',
      this._viewModel.length
    );
  },

  _getFirstItemName: function() {
    if (!this.options.viewModel) return;

    var firstItem = this.options.viewModel.at(0);

    if (firstItem) {
      return firstItem.get("name");
    }
  }

});
