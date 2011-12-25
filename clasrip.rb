require "nokogiri"
require "net/http"

module Console
	def self.set_title(title)
		$stdout << "\x1b]2;#{title}\x07"
	end
end

# DB = Sequel.sqlite

# DB.create_table :classifications do
#	primary_key :id
#	String :title
#	String :media
#	String :category
#	String :classification
#	Date :date
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
		attr_accessor :host, :port
		def initialize(output_xml)
			@host_url = "www.classification.gov.au"
			@query_url = "/www/cob/find.nsf/classifications?search&searchwv=1&searchmax=1000&count=1000&query=(%%5BclassificationDate%%5D%%3E=%s)AND(%%5BclassificationDate%%5D%%3C%s)"
			@xml_file = output_xml
			@xml_doc = Nokogiri::XML::Document.new
			@xml = Nokogiri::XML("<classifications/>")
		end

		def start(start_year, end_year)
			conn = Net::HTTP.new(@host_url, 80)
			conn.start

			date1 = DatesBetween.new(start_year, end_year)
			date2 = DatesBetween.new(start_year, end_year)
			date2.next

			date1.each do |first_date| 
				second_date = date2.next
				puts first_date + " -> " + second_date
				Console::set_title "#{first_date} -> #{second_date}"
				
				res = conn.get(@query_url % [date1.to_s, date2.to_s])
				
				html = Nokogiri::HTML(res.read_body)
				table = get_table_element(html) or next #check this works

				table.xpath("tr").each do |row|
					row.children[0].node_name == "td" or next
					title = Nokogiri::XML::Node.new("title", @xml_doc)
					title.content = row.xpath('td[2]/a').first.content
					
					url = Nokogiri::XML::Node.new("url", @xml_doc)
					url.content = row.xpath('td[2]/a').first['href']
					
					media = Nokogiri::XML::Node.new("media", @xml_doc)
					media.content = row.xpath('td[3]').first.content
					
					category = Nokogiri::XML::Node.new("category", @xml_doc)
					category.content = row.xpath('td[4]').first.content
					
					date = Nokogiri::XML::Node.new("date", @xml_doc)
					date.content = row.xpath('td[5]').first.content #TODO
					
					classification = Nokogiri::XML::Node.new("rating", @xml_doc)
					res = conn.get(url.content)
					html = Nokogiri::HTML(res.read_body)
					classification.content = get_classification(html)

					node = Nokogiri::XML::Node.new("classification", @xml_doc)
					[title, url, media, category, date, classification].each do |n|
						node << n
					end
					puts node
					@xml.root << node
				end
				File.open(@xml_file, 'w') do |f|
					bytes = f.write(@xml.to_xml)
					puts "Wrote #{bytes} bytes to #{@xml_file}"
				end
			end
		end

		private
		def get_table_element(doc)
			doc.xpath("/html/body/form/div[3]/div[2]/div/div/table").first
		end
		
		def get_classification(doc)
			doc.xpath("/html/body/form/div[3]/div[2]/div/div/div/div[2]").first.text
		end
	end
end
