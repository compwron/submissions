# encoding: UTF-8
class Ability
  include CanCan::Ability

  def initialize(user, conference, params={})
    @user = user || User.new # guest
    @conference = conference
    @params = params

    alias_action :edit, :update, :destroy, :to => :modify

    guest
    admin if @user.admin?
    author if @user.author?
    organizer if @user.organizer?
    reviewer if @user.reviewer?
  end

  private

  def guest
    can(:read, User)
    can(:read, Comment)
    can(:read, Session)
    can(:read, Track)
    can(:read, SessionType)
    can(:read, AudienceLevel)
    can(:read, ActsAsTaggableOn::Tag)
    can(:read, 'static_pages')
    can(:manage, 'password_resets')
    can(:create, User)
    can(:update, User, :id => @user.id)
    can(:create, Comment)
    can(:modify, Comment, :user_id => @user.id)
    can(:manage, 'accept_reviewers') do
      find_reviewer.try(:user) == @user && find_reviewer.try(:invited?)
    end
    can(:manage, 'reject_reviewers') do
      find_reviewer.try(:user) == @user && find_reviewer.try(:invited?)
    end
  end

  def admin
    can(:manage, :all)
    # Revoke these actions, to use the ones appropriate for each role, below
    cannot(:create, ReviewDecision)
    cannot(:update, ReviewDecision)
    cannot(:create, Review)
    cannot(:create, FinalReview)
    cannot(:create, EarlyReview)
    cannot(:manage, 'confirm_sessions')
    cannot(:manage, 'withdraw_sessions')
  end

  def author
    can do |action, subject_class, subject|
      expand_actions([:create]).include?(action) && subject_class == Session && @conference.in_submission_phase?
    end
    can(:update, Session) do |session|
      session.try(:conference) == @conference && session.try(:is_author?, @user) && @conference.in_submission_phase?
    end
    can do |action, subject_class, subject, session|
      session = find_session if session.nil?
      expand_actions([:index]).include?(action) &&
          subject_class == FinalReview &&
          session.try(:is_author?, @user) && session.review_decision.try(:published?)
    end
    can(:manage, 'confirm_sessions') do
      find_session && find_session.try(:is_author?, @user) && find_session.pending_confirmation? && find_session.review_decision && Time.zone.now <= @conference.author_confirmation
    end
    can(:manage, 'withdraw_sessions') do
      find_session && find_session.try(:is_author?, @user) && find_session.pending_confirmation? && find_session.review_decision && Time.zone.now <= @conference.author_confirmation
    end
  end

  def organizer
    can(:manage, Reviewer)
    can(:read, "organizer_sessions")
    can(:read, 'reviews_listing')
    can(:index, ReviewDecision)
    can(:cancel, Session) do |session|
      session.can_cancel? && @user.organized_tracks(@conference).include?(session.track)
    end
    can(:show, Review)
    can(:show, FinalReview)
    can(:show, EarlyReview)
    can do |action, subject_class, subject|
      expand_actions([:organizer]).include?(action) && subject_class == FinalReview &&
          @user.organized_tracks(@conference).include?(find_session.try(:track))
    end
    can do |action, subject_class, subject, session|
      session = find_session if session.nil?
      expand_actions([:create]).include?(action) && subject_class == ReviewDecision &&
          session.try(:in_review?) && @user.organized_tracks(@conference).include?(session.track) && Time.zone.now > @conference.review_deadline
    end
    can do |action, subject_class, subject, session|
      session = find_session if session.nil?
      expand_actions([:update]).include?(action) && subject_class == ReviewDecision &&
          !session.try(:author_agreement) && (session.try(:pending_confirmation?) || session.try(:rejected?)) && @user.organized_tracks(@conference).include?(session.track) && Time.zone.now > @conference.review_deadline
    end
  end

  def reviewer
    can(:read, 'reviewer_sessions')
    can(:show, Review, :reviewer_id => @user.id)
    can(:show, FinalReview, :reviewer_id => @user.id)
    can(:show, EarlyReview, :reviewer_id => @user.id)
    can do |action, subject_class, subject, session|
      session = find_session if session.nil?
      expand_actions([:create]).include?(action) && subject_class == FinalReview &&
          Session.for_reviewer(@user, @conference).include?(session) && @conference.in_final_review_phase?
    end
    can(:read, 'reviews_listing')
    can(:reviewer, 'reviews_listing')
  end

  def find_session
    @session ||= Session.find(@params[:session_id]) if @params[:session_id].present?
  end

  def find_reviewer
    @reviewer ||= Reviewer.find(@params[:reviewer_id]) if @params[:reviewer_id].present?
  end
end
