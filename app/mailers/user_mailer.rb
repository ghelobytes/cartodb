class UserMailer < ActionMailer::Base
  default from: "cartodb.com <support@cartodb.com>"
  layout 'mail'

  def new_organization_user(user)
    @user = user
    @organization = @user.organization
    @owner = @organization.owner
    @subject = "You have been invited to CartoDB organization '#{@organization.name}'"

    if @user.enable_account_token.nil?
      @link = "#{CartoDB.base_url(@organization.name, @user.username)}"
    else
      @enable_account_link = "#{CartoDB.base_url(@organization.name, @user.username)}#{CartoDB.path(self, 'enable_account_token_show', {id: @user.enable_account_token})}"
    end

    # INFO: if user has been created by the admin he needs to tell him the password. If he has signed in through the page
    @user_needs_password = !@user.google_sign_in && @user.enable_account_token.nil?

    mail :to => @user.email, 
         :subject => @subject
  end

  def share_table(table, user)
    @table_visualization = table
    @user = user
    organization = @table_visualization.user.organization
    @link = "#{CartoDB.base_url(organization.name, @user.username)}#{CartoDB.path(self, 'public_tables_show_bis', {id: "#{@table_visualization.user.username}.#{@table_visualization.name}"})}"
    @subject = "#{@table_visualization.user.username} has shared a CartoDB dataset with you"
    @unsubscribe_link = generate_unsubscribe_link(user, Carto::Notification::SHARE_TABLE_NOTIFICATION)
    mail :to => @user.email, 
         :subject => @subject
  end
  
  def share_visualization(visualization, user)
    @visualization = visualization
    @user = user
    organization = @visualization.user.organization
    @link = "#{CartoDB.base_url(organization.name, @visualization.user.username)}#{CartoDB.path(self, 'public_visualizations_show_map', {id: @visualization.id})}"
    @unsubscribe_link = generate_unsubscribe_link(user, Carto::Notification::SHARE_VISUALIZATION_NOTIFICATION)
    @subject = "#{@visualization.user.username} has shared a CartoDB map with you"
    mail :to => @user.email,
         :subject => @subject
  end

  def unshare_table(table_visualization_name, table_visualization_owner_name, user)
    @table_visualization_name = table_visualization_name
    @table_visualization_owner_name = table_visualization_owner_name
    @user = user
    @subject = "#{@table_visualization_owner_name} has stopped sharing a CartoDB dataset with you"
    @unsubscribe_link = generate_unsubscribe_link(user, Carto::Notification::UNSHARE_TABLE_NOTIFICATION)
    mail :to => @user.email,
         :subject => @subject
  end
  
  def unshare_visualization(visualization_name, visualization_owner_name, user)
    @visualization_name = visualization_name
    @visualization_owner_name = visualization_owner_name
    @user = user
    @subject = "#{@visualization_owner_name} has stopped sharing a CartoDB map with you"
    @unsubscribe_link = generate_unsubscribe_link(user, Carto::Notification::UNSHARE_VISUALIZATION_NOTIFICATION)
    mail :to => @user.email,
         :subject => @subject
  end

  def map_liked(visualization, viewer_user)
    @user = visualization.user
    @map_name = visualization.name
    @viewer_name = viewer_user.name.nil? ? viewer_user.username : viewer_user.name
    @subject = "#{@viewer_name} has fall in love with your map called #{@map_name}"
    @link = "#{@user.public_url}#{CartoDB.path(self, 'public_tables_show', { id: visualization.id })}"
    @unsubscribe_link = generate_unsubscribe_link(@user, Carto::Notification::MAP_LIKE_NOTIFICATION)
    mail :to => @user.email,
         :subject => @subject
  end

  private

  def generate_unsubscribe_link(user, notification_type)
    hash = Carto::UserNotification.generate_unsubscribe_hash(user, notification_type)
    return "#{user.public_url}#{CartoDB.path(self, 'notifications_unsubscribe', { notification_hash: hash })}"
  end

end
