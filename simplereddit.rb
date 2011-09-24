#!/usr/bin/ruby -rubygems

require 'net/http'
require 'uri'
require 'json'
require 'yaml/store'


$request_interval = 2.0
$sesscook = {}
$store = YAML::Store.new("#{ENV['HOME']}/.simple_reddit.yml")

def wait_next_action
  if $last_action
    time_since_last = Time.now - $last_action 
    time_till_next = $request_interval - time_since_last
    if time_till_next > 0
      #puts "sleeping #{time_till_next} seconds..."
      sleep time_till_next
    end
  end
  $last_action = Time.now
  yield
end


def grab_sesscook(user, pass, http)
  sesscook = nil
  $store.transaction do | s |
    s['reddit_cookies'] ||= {}
    sesscook = s['reddit_cookies'][user]
  end
  unless sesscook
    puts "fetching session cookie for #{user}"
    req = Net::HTTP::Post.new('/api/login')
    req.form_data = { 'user' => user, 'passwd' => pass };
    resp = wait_next_action { http.request(req) }
    sesscook = resp['set-cookie'].split('; ').map{ |_| _.split('=')}.assoc('reddit_session').join('=')
    $store.transaction { |s| s['reddit_cookies'][user] = sesscook }
  end
  return sesscook
end

def print_message(msg)
  puts "from #{msg['data']['author']}"
  if msg['was_comment'] == true
    puts "Comment"
  end
  puts "body:\n#{msg['data']['body']}"
  puts "context: http://www.reddit.com#{msg['data']['context']}"
end

def get_unread(user, pass, http)
  sesscook ||= grab_sesscook(user, pass, http)
  headers = { 'User-Agent' => 'simple reddit checker', 'Cookie' => sesscook }
  resp = wait_next_action { http.get('/message/unread.json', headers) }
  resp_parsed = JSON.parse(resp.body)
  if resp_parsed['data']['children'].length > 0
    puts JSON.pretty_generate(resp_parsed)
    resp_parsed['data']['children'].each do | msg |
      print_message(msg)
    end
  else
    puts "no unread messages"
  end
end


userlist = nil
$store.transaction do |s|
  userlist = s['users']
  unless userlist
    s['users'] = [['exampleuser1', 'examplepass1'],['exampleuser2', 'examplepass2']]
    raise "please edit .simple_reddit.yml with real user info"
  end
end

if /-c/i.match(ARGV[0])
  def do_it
    while true
      #print "\033[2J"
      system "clear"
      puts Time.now
      yield
      puts "sleeping for 60s...."
      sleep 60
    end
  end
else
  def do_it
    yield
  end
end
  
do_it do
  Net::HTTP.start('www.reddit.com') do | http |
    userlist.each do | user, pw |
      puts "#{user}..."
      get_unread(user, pw, http)
    end
  end
end
