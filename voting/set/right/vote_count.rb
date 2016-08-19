# session vote won't be saved to real vote count until user login
# users will see a different vote count as the vote from anonymous would be
# counted in rendering the vote count
def session_vote?
  # override with true to allow voting for users who are not logged in
  # and save votes in session
  false
end

#def history?
#  false
#end

def downvoted_in_session?
  Env.session[:down_vote] && Env.session[:down_vote].include?(left.id)
end

def upvoted_in_session?
  Env.session[:up_vote] && Env.session[:up_vote].include?(left.id)
end

def votee
  cardname.left
end

# The voted card ids will be stored in a pointer card. insert_before_id is used
# to add the id in front of another id.
# it may just affect the showing order of the the votes only.
# In wikirate, insert_before_id is used while a votable card is dragged and
# dropped in user's profile.
# it will insert the card to specific position in the pointer card which
# contains what users voted
def vote_up insert_before_id=false
  if Auth.signed_in?
    Auth.as_bot do
      # binding.pry
      case vote_status
      when '?'
        uv_card = Auth.current.upvotes_card
        add_vote uv_card, left.id, insert_before_id
      when '-'
        dv_card = Auth.current.downvotes_card
        delete_vote dv_card, left.id
      end
    end
  elsif session_vote?
    if downvoted_in_session?
      Env.session[:down_vote].delete left.id
    else
      add_vote_to_session :up_vote, left.id, insert_before_id
    end
  end
end

def vote_down insert_before_id=false
  if Auth.signed_in?
    Auth.as_bot do
      case vote_status
      when '?'
        dv_card = Auth.current.downvotes_card
        add_vote dv_card, left.id, insert_before_id
      when '+'
        uv_card = Auth.current.upvotes_card
        delete_vote uv_card, left.id
      end
    end
  elsif session_vote?
    if upvoted_in_session?
      Env.session[:up_vote].delete left.id
    else
      add_vote_to_session :down_vote, left.id, insert_before_id
    end
  end
end

def add_vote vote_card, votee_id, insert_before_id=false
  if insert_before_id
    vote_card.insert_id_before votee_id, insert_before_id
    add_subcard vote_card
    # vote_card.save!
    update_votecount
  elsif vote_card.add_id votee_id
    # vote_card.save!
    add_subcard vote_card
    update_votecount
  end
end

def delete_vote vote_card, votee_id
  if vote_card.drop_id votee_id
    # vote_card.save!
    add_subcard vote_card
    update_votecount
  end
end

def add_vote_to_session vote_type, votee_id, insert_before_id
  Env.session[vote_type] ||= []
  Env.session[vote_type].delete(votee_id)
  if insert_before_id &&
     (index = Env.session[vote_type].index(insert_before_id))
    Env.session[vote_type].insert(index, votee_id)
  else
    Env.session[vote_type] << votee_id
  end
end

def force_up insert_before_id=false
  vote_up insert_before_id
  vote_up(insert_before_id) if vote_status != '+'
end

def force_down insert_before_id=false
  vote_down insert_before_id
  vote_down(insert_before_id) if vote_status != '-'
end

def force_neutral insert_before_id=false
  case vote_status
  when '-'
    vote_up insert_before_id
  when '+'
    vote_down insert_before_id
  end
end

def raw_content
  if !Auth.signed_in? && session_vote?
    if Env.session[:up_vote] && Env.session[:up_vote].include?(left.id)
      return (content.to_i + 1).to_s
    elsif Env.session[:down_vote] && Env.session[:down_vote].include?(left.id)
      return (content.to_i - 1).to_s
    end
  end
  super
end

def direct_contribution_count
  return left.upvote_count.to_i + left.downvote_count.to_i
end

def update_votecount
  up_count = Auth.as_bot do
              Card.search(
                right_plus: [{ codename: 'upvotes' }, link_to: left.name],
                return: 'count'
              )
            end
  down_count = Auth.as_bot do
                 Card.search(
                   right_plus: [{ codename: 'downvotes' }, link_to: left.name],
                   return: 'count'
                 )
               end
  # loop the subcards and see if left is inside
  subcards.each do |subcard|
    case subcard.right.codename
    when :upvotes.to_s
      up_count += 1 if subcard.item_cards.any? {|c| c.id == left.id}
    when :downvotes.to_s
      down_count += 1 if subcard.item_cards.any? {|c| c.id == left.id}
    end
  end
  uvc = left.upvote_count_card
  uvc.auto_content = true
  subcards.add uvc.name, content: up_count.to_s

  dvc = left.downvote_count_card
  dvc.auto_content = true
  subcards.add dvc.name, content: down_count.to_s

  self.content = (up_count - down_count).to_s
  self.auto_content = true
end

def vote_status
  if Auth.signed_in?
    if Auth.current.upvotes_card.include_item? "~#{left.id}"
      '+'
    elsif Auth.current.downvotes_card.include_item? "~#{left.id}"
      '-'
    else
      '?'
    end
  elsif session_vote?
    if upvoted_in_session?
      '+'
    elsif downvoted_in_session?
      '-'
    else
      '?'
    end
  else
    '#'
  end
end

event :vote, :prepare_to_validate,
      on: :update,
      when: proc { |c| Env.params['vote'] } do
  if Auth.signed_in? || session_vote?
    successor_id = Env.params['insert-before'] &&
                   Env.params['insert-before'].to_i
    case Env.params['vote']
    when 'up' then vote_up successor_id
    when 'down' then vote_down successor_id
    when 'force-up' then force_up successor_id
    when 'force-down' then force_down successor_id
    when 'force-neutral' then force_neutral successor_id
    end

    abort :success if !Auth.signed_in? && session_vote?
  else
    path_hash = { action: :update, vote: Env.params['vote'],
                  success: '*previous' }
    uri = format.page_path cardname, path_hash
    Env.save_interrupted_action uri
    abort success: "REDIRECT: #{Card[:signin].cardname.url_key}"
  end
end

format :html do
  view :missing  do |args|
    if card.new_card? && (l=card.left) && l.respond_to?(:vote_count)
      Auth.as_bot do
        card.update_votecount
        card.save!
      end
      render(args[:denied_view], args)
    else
      super(args)
    end
  end

  view :new, :missing

  view :content do |args|
    wrap args.merge(slot_class: 'card-content nodblclick') do
      [
        _optional_render(:menu, args, :hide),
        wrap_with(:div, class: 'vote-up') { vote_up_link(:content) },
        _render_core(args),
        wrap_with(:div, class: 'vote-down') {vote_down_link(:content) }
      ]
    end
  end

  view :core do |args|
    wrap_with :div, class: 'vote-count' do
      super(args)
    end
  end

  view :details do |args |
    wrap args.merge(slot_class: 'nodblclick') do
      [
        wrap_with(:div, class: 'vote-up') do
          [
            vote_up_link(:details),
            up_details
          ]
        end,
        _render_core(args),
        wrap_with(:div, class: 'vote-down') do
          [
            vote_down_link(:details),
            down_details
          ]
        end
      ]
    end
  end

  def vote_up_link success_view
    link = case card.vote_status
    when '+'
      disabled_vote_link :up, 'You have already upvoted this claim.'
    else
      vote_link '<i class="fa fa-angle-up"></i>', 'Vote up', :up, success_view
    end
  end

  def vote_down_link success_view
    link = case card.vote_status
    when '-'
      disabled_vote_link :down, 'You have already downvoted this claim.'
    else
      vote_link '<i class="fa fa-angle-down"></i>', 'Vote down', :down,
                success_view
    end
  end

  def disabled_vote_link up_or_down, message, extra={}
    button_tag({disabled: true,
        class: 'slotter disabled-vote-link vote-button', type: 'button', title: message}.merge(extra)) do
      "<i class=\"fa fa-angle-#{up_or_down} \"></i>"
    end
  end

  def vote_link text, title, up_or_down, view, extra={}
    button_tag({href: vote_path(up_or_down, view),
        class: 'slotter vote-link vote-button', type: 'button', title: title, remote: true, method: 'post'}.merge(extra)) do
      text
    end
  end

  def vote_path up_or_down=nil, view='content'
    path_hash = {name: card.name, action: :update, view: view}
    path_hash[:vote] = up_or_down if up_or_down
    path path_hash
  end

  def up_details
    render_haml up_count: card.left.upvote_count do %{
%span.vote-details
  <i class="fa fa-users"></i>
  %span.vote-number
    = up_count
  Important
      }
    end
  end

  def down_details
    render_haml down_count: card.left.downvote_count do %{
%span.vote-details
  <i class="fa fa-users"></i>
  %span.vote-number
    = down_count
  Not important
      }
    end
  end
end
