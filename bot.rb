require 'railsbot'
class Bot < Summer::Connection
  include ApiLookups
  
  def did_start_up
    ActiveRecord::Base.establish_connection(config['database'])
  end

  # before_filter :check_for_new_day
  def authorize_command(sender, reply_to, msg)
    return unless authorized?(sender[:nick]) && sender[:nick].downcase == "radar"
    p = Person.find_or_create_by_nick(msg.downcase)
    p.authorized = true
    p.save!
    privmsg("#{msg} is now authorized to (ab)use me.", sender[:nick])
  end

  def gitlog_command(sender, reply_to, msg)
    return unless authorized?(sender[:nick])
    privmsg(`git log -1`.split("\n").first, reply_to)
  end


  def tip_command(sender, reply_to, command, options={})
    return unless authorized?(sender[:nick])
    if tip = Tip.find_by_command(command.strip) 
      tip.text.gsub!("{nick}", sender[:nick])
      message = tip.text
      message = "#{options[:directed_at]}: #{message}" if options[:directed_at]
      privmsg(message, reply_to)
    end
  end
  
  def seen_command(sender, reply_to, nick)
    return unless authorized?(sender[:nick])
    if sender[:nick].downcase == nick.downcase
      privmsg("Looked in a mirror recently? Oh? Poor mirror.", reply_to)
    else
      last_chat = p.messages.first(:order => "created_at DESC") if p
      if last_chat
        time = last_chat.created_at.strftime("%d %B %Y, %H:%M%p")
        privmsg("I last saw #{nick} on ##{last_chat.channel.name} at #{time} (UTC), they said #{last_chat.text.inspect}", reply_to)
      else
        privmsg("Who's #{nick}?", reply_to)
      end
    end
  end

  def join_command(sender, reply_to, msg)
    join(msg) if authorized?(sender[:nick])
  end

  def say_command(sender, reply_to, msg)
    return unless authorized?(sender[:nick])
    msg = msg.split(" ")
    privmsg(msg[1..-1].join(" "), msg.first)
  end

  def part_command(sender, reply_to, msg)
    part(msg) if authorized?(sender[:nick])
  end

  def google_command(sender, reply_to, msg, opts={})
    search("http://www.google.com/search", sender, msg, reply_to, opts)
  end

  alias :g_command :google_command 

  def gg_command(sender, reply_to, msg, opts={})
    search("http://www.letmegooglethatforyou.com/", sender, msg, reply_to, opts)
  end

  def railscast_command(sender, reply_to, msg, opts={})
    search("http://railscasts.com/episodes", sender, msg, reply_to, opts, "search")
  end

  def githubs_command(sender, reply_to, msg, opts={})
    search("http://github.com/search", sender, msg, reply_to, opts)
  end

  def github_command(sender, reply_to, msg, opts={})
    parts = msg.split(" ")
    if parts.empty?
      message = "http://github.com - Social code hosting using Git"
    else
      message = "http://github.com/#{parts[0]}/#{parts[1]}/"
      message += "tree/#{parts[2]}" if parts[2]
      message += "/#{parts[3..-1].join("/")}" if !parts[3].nil?
    end
    direct_at(reply_to, message, opts[:directed_at])
  end
  
  def add_command(sender, channel, message, opts={})
    return unless authorized?(sender[:nick])
    message = message.split(" ")
    Tip.find_by_command(message[0]) || Tip.create!(:command => message[0], :text => message[1..-1].join(" "))
    privmsg("The !#{message[0]} command is now available.", channel == me ? sender[:nick] : channel)
  end
  
  
  def channel_message(sender, channel, message, options={})
    find_or_create_person(sender[:nick])
    # need to log before everything else, other commands also trigger messages
    # log(channel, sender[:nick], message)
    # try to match a non-existent command which might be a tip
    if m = /^(([^:]+)[:|,])?\s?!([^\s]+)\s?(.*)?/.match(message)
      cmd_sym = "#{m[3]}_command".to_sym
      # if we don't respond to this command then it's likely a tip
      if respond_to?(cmd_sym)
        if !m[2].nil?
          send(cmd_sym, sender, channel, m[4], { :directed_at => m[2] })
        end
      else
        tip_command(sender,channel, m[3], { :directed_at => m[2] })
      end
    end

    if m = /^(([^:]+)[:|,])?\s?##(.+)/.match(message)
      return unless authorized?(sender[:nick])
      # send(:lookup_command, sender, channel, m[3], { :directed_at => m[2] })
    end

  end
  
  alias_method :private_message, :channel_message

  private

  def log(channel, sender, message)
    channel = Channel.find_or_create_by_name(channel.gsub("#", ''))
    channel.messages.create!(:person => Person.find_or_create_by_nick(sender), :text => message)
  end

  def direct_at(reply_to, message, who=nil)
    message = who + ": #{message}" if who
    privmsg(message, reply_to)
  end

  def search(host, sender, msg, reply_to, opts, query_parameter="q")
    message = "#{host}?#{query_parameter}=#{msg.split(" ").join("+")}"
    direct_at(reply_to, message, opts[:directed_at])
  end

  # Who's there?

  def authorized?(nick)
    Person.find_by_nick_and_authorized(nick.downcase, true)
  end

  # def check_for_new_day_filter(host, sender, msg, reply_to, opts)
  #   @day = Day.find_or_create_by_date(Date.today) if @today!=Date.today
  #   @today = Date.today
  #   @day.increment!("chats_count")
  # end

  def find_or_create_person(nick)
    Person.find_or_create_by_nick(nick)
  end

    
end


Bot.new(ARGV[0])