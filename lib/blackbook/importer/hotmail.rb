require 'blackbook/importer/page_scraper'
require 'cgi'

##
# imports contacts for MSN/Hotmail
class Blackbook::Importer::Hotmail < Blackbook::Importer::PageScraper

  DOMAINS = { "compaq.net"        => "https://msnia.login.live.com/ppsecure/post.srf",
              "hotmail.co.jp"     => "https://login.live.com/ppsecure/post.srf",
              "hotmail.co.uk"     => "https://login.live.com/ppsecure/post.srf",
              "hotmail.com"       => "https://login.live.com/ppsecure/post.srf",
              "hotmail.de"        => "https://login.live.com/ppsecure/post.srf",
              "hotmail.fr"        => "https://login.live.com/ppsecure/post.srf",
              "hotmail.it"        => "https://login.live.com/ppsecure/post.srf",
              "live.com"          => "https://login.live.com/ppsecure/post.srf",
              "messengeruser.com" => "https://login.live.com/ppsecure/post.srf",
              "msn.com"           => "https://msnia.login.live.com/ppsecure/post.srf",
              "passport.com"      => "https://login.live.com/ppsecure/post.srf",
              "webtv.net"         => "https://login.live.com/ppsecure/post.srf",
            }
              
  LIVE_DOT_COM = /live.com|live.([a-z]{2})|live.com.([a-z]{2})/
  ##
  # Matches this importer to an user's name/address

  def =~(options)
    return false unless options && options[:username]
    domain = username_domain(options[:username].downcase)
    !domain.empty? && (DOMAINS.keys.include?( domain ) or LIVE_DOT_COM =~ domain) ? true : false
  end
   
  ##
  # Login procedure
  # 1. Go to login form
  # 2. Set login and passwd
  # 3. Set PwdPad to IfYouAreReadingThisYouHaveTooMuchFreeTime minus however many characters are in passwd (so if passwd
  #    was 8 chars, you'd chop 8 chars of the end of IfYouAreReadingThisYouHaveTooMuchFreeTime - giving you IfYouAreReadingThisYouHaveTooMuch)
  # 4. Set the action to the appropriate URL for the username's domain
  # 5. Get the query string to append to the new action
  # 5. Submit the form and parse the url from the resulting page's javascript
  # 6. Go to that url

  def login
    page = agent.get('http://login.live.com/login.srf?id=2')
    form = page.forms.first
    form.login   = options[:username]
    form.passwd  = options[:password]
    form.PwdPad  = ( "IfYouAreReadingThisYouHaveTooMuchFreeTime"[0..(-1 - options[:password].to_s.size )])
    query_string = page.body.scan(/g_QS="([^"]+)/).first.first rescue nil
    form.action  = login_url + "?#{query_string.to_s}"
    page = agent.submit(form)
    
    # Check for login success
    if page.body =~ /The e-mail address or password is incorrect/ ||
      page.body =~ /Sign in failed\./
      raise( Blackbook::BadCredentialsError, 
        "That username and password was not accepted. Please check them and try again." )
    end
    
    @first_page = agent.get( page.body.scan(/http\:\/\/[^"]+/).first )
  end
  
  ##
  # prepare this importer

  def prepare
    login
  end
  
  ##
  # Scrape contacts for Hotmail
  # Seems like a POST to directly fetch CSV contacts from options.aspx?subsection=26&n=
  # raises an end of file error in Net::HTTP via Mechanize.
  # Seems like Hotmail addresses are now hosted on Windows Live.

  def scrape_contacts
    unless agent.cookies.find{|c| c.name == 'MSPPre' && c.value == options[:username]}
      raise( Blackbook::BadCredentialsError, "Must be authenticated to access contacts." )
    end
    page = agent.get(@first_page.iframes.first.src)
    
    page = agent.click(page.link_with(:text => 'Mail'))
    page = agent.get(page.iframes.first.src)
    page = agent.get('/mail/PrintShell.aspx?type=contact')
        
    rows = page.search("//div[@class='ContactsPrintPane cPrintContact BorderTop']")
    rows.collect do |row|
      vals = {}
      row.search("table/tr").each do |pair|
        key = pair.search("td[@class='TextAlignRight Label']").first.inner_text.strip rescue nil
        next if key.nil?
        val = pair.search("td[@class='Value']").first.inner_text.strip
        vals[key.to_sym] = val
      end
      vals[:name] = vals['Name:'.to_sym] rescue ''
      vals[:email] = (vals['Personal e-mail:'.to_sym] || vals['Work e-mail:'.to_sym] || vals['Windows Live ID:'.to_sym]).split(' ').first rescue ''
      vals
    end
  end
  
  ##
  # lookup for the login service that should be used based on the user's
  # address

  def login_url
    DOMAINS[username_domain] || DOMAINS['hotmail.com']
  end
  

  ##
  # normalizes the host for the page that is currently being "viewed" by the
  # Mechanize agent

  def current_host
    return nil unless agent && agent.current_page
    uri = agent.current_page.uri
    "#{uri.scheme}://#{uri.host}"
  end
  
  ##
  # determines the domain for the user

  def username_domain(username = nil)
    username ||= options[:username] if options
    return unless username
    username.to_s.split('@').last
  end
  
  Blackbook.register(:hotmail, self)
end
