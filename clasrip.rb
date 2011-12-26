require "nokogiri"
require "net/http"

module Console
  def self.set_title(title)
    $stdout << "\x1b]2;#{title}\x07"
  end
end

# DB = Sequel.sqlite

# DB.create_table :classifications do
# primary_key :id
# String :title
# String :media
# String :category
# String :classification
# Date :date
# end
module Clasrip
  class DatesBetween
    def initialize(start, finish)
      @year = start
      @finish = finish
      @month = 0
    end

    def to_s
      "1/#{@month}/#{@year}"
    end

    def next
      raise StopIteration if @year >= @finish
      if @month >= 12
        @month = 0
        @year += 1
      end
      @month += 1
      to_s 
    end

    def each
      loop do
        yield self.next
      end
    rescue StopIteration
      self
    end
  end
  
  
  class Ripper
    def initialize(output_xml)
      @host_url = "www.classification.gov.au"
      @query_url = "/www/cob/find.nsf/classifications?search&searchwv=1&searchmax=1000&count=1000&query=(%%5BclassificationDate%%5D%%3E=%s)AND(%%5BclassificationDate%%5D%%3C%s)"
      @xml_file = output_xml
      @xml = Nokogiri::XML("<classifications/>")
    end
    
    def new_conn
      @conn = Net::HTTP.new(@host_url, 80)
      @conn.start
    end

    def start(start_year, end_year)
      new_conn

      date1 = DatesBetween.new(start_year, end_year)
      date2 = DatesBetween.new(start_year, end_year)
      date2.next

      date1.each do |first_date| 
        second_date = date2.next
        puts first_date + " -> " + second_date
        Console::set_title "#{first_date} -> #{second_date}"
        
        begin
          res = @conn.get(@query_url % [date1.to_s, date2.to_s])
        rescue
          new_conn
          retry
        end

        html = Nokogiri::HTML(res.read_body)
        table = html.css("#results > table").first or next

        table.xpath("tr").each do |row|
          row.children[0].node_name == "td" or next
          node = Nokogiri::XML::Node.new("classification", @xml)
          
          title = Nokogiri::XML::Node.new("title", @xml)
          title.content = row.xpath('td[2]/a').first.content
          
          url = Nokogiri::XML::Node.new("url", @xml)
          url.content = row.xpath('td[2]/a').first['href']
          
          published_date = Nokogiri::XML::Node.new("published_date", @xml)
          published_date.content = row.xpath('td[5]').first.content
          
          [title, url, published_date].each do |n|
            node << n
          end
          
          # Get the page for this row to get the rest of the content
          begin
            res = @conn.get(url.content)
          rescue
            new_conn
            retry
          end
          html = Nokogiri::HTML(res.read_body)
          form = html.css(".fform").first or next

          form.css(".frow").each do |row|
            label = row.css(".flabel").first.content.strip.downcase.gsub(" ", "-")
            field = row.css(".ffield").first.content.strip.gsub("\u00A0", "")
            
            n = Nokogiri::XML::Node.new(label, @xml)
            n.content = field

            node << n
          end

          puts node
          @xml.root << node
        end

        File.open(@xml_file, 'w') do |f|
          file = @xml.write_xml_to f
          puts "Wrote #{file.size} bytes to #{@xml_file}"
        end
      end
    end
  end
end

if ARGV.size < 1
  puts "Usage: #{File.basename($0)} <output-xml>"
else
  require "date"
  Clasrip::Ripper.new(ARGV[0]).start(1971, Date.today.year + 1)
end
