class Topic < ActiveRecord::Base
  include Notifiable

  DEFAULT_HIT = 0
  default_value_for :hit, DEFAULT_HIT
  default_value_for :content, ''
  default_value_for :involved_at do
    Time.zone.now
  end

  belongs_to :channel
  belongs_to :user
  has_many :comments, :as => :commentable, :dependent => :destroy
  has_many :bookmarks, :as => :bookmarkable, :dependent => :destroy
  has_many :notifications, :as => :notifiable, :dependent => :destroy

  validates :channel_id, :user_id, :title, :presence => true

  after_create :send_notifications

  def last_comment
    self.comments.order('created_at ASC').last
  end

  def locked?
    Time.now - self.created_at > Siteconf.topic_editable_period
  end

  def allow_modification_by?(user)
    (!locked? && self.user == user) || user.can_manage_site?
  end

  def notifiable_title
    title
  end

  def notifiable_path
    "/t/#{id}"
  end

  def self.sticky_topics
    with_sticky(true).order('updated_at DESC').all
  end

  def self.home_topics(num)
    with_sticky(false).latest_involved_topics(num)
  end

  def self.with_sticky(sticky)
    where(:sticky => sticky)
  end

  def self.latest_involved_topics(num)
    order('involved_at DESC').limit(num).all
  end

  def self.recent_topics(num)
    ts = select('updated_at').order('updated_at DESC').first.try(:updated_at)
    return Rabel::Model::EMPTY_DATASET unless ts.present?
    Rails.cache.fetch("topics/recent/#{self.count}/#{num}-#{ts}") do
      order('involved_at DESC').limit(num).all
    end
  end

  def mention_check_text
    self.title + self.content
  end

  def mentioned_users
    mentioned_names = self.mention_check_text.scan(Notifiable::MENTION_REGEXP).collect {|matched| matched.first}.uniq
    mentioned_names.delete(self.user.nickname)
    mentioned_names.map { |name| User.find_by_nickname(name) }.compact
  end

  def prev_topic(node)
    node.topics.where(['id < ?', self.id]).order('created_at DESC').first
  end

  def next_topic(node)
    node.topics.where(['id > ?', self.id]).order('created_at ASC').first
  end

  private

    def send_notifications
      mentioned_users.each do |user|
        Notification.notify(
          user,
          self,
          self.user,
          Notification::ACTION_TOPIC,
          self.content
        )
      end
    end

end
