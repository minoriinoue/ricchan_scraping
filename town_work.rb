require 'nokogiri'
require 'open-uri'
require 'natto'
require 'csv'
require 'pry'
require 'rb-readline'

natto = Natto::MeCab.new
doc = Nokogiri::HTML(open('https://townwork.net/tokyo'))

area_to_code = {} #新宿区 to 52101
jc_to_jmc_to_code = {} #飲食/フード to {ファミレス・レストラン(ホールスタッフ) : 00113}
jmc_to_code_arr = []
doc.css('.sch-panel-tab4-wrap').each do |panel|
  panel.css('.contents-box-inner').each do |block|
    i = 0
    block.css('.panel-tbl-wrap').each do |dls|
      break if i == 2
      if i == 0 # area code
        dls.css('option').each do |area|
          if area.inner_text != "選択してください"
            area_to_code[area.inner_text] = area["value"][1..-1]
          end
        end
      end


      if i == 1 # job category code
        j = 0
        dls.css('dd div select').each do |jc|
          j += 1
          next if j-1 == 0 # Skip sentaku shitekudasai

          jmc_to_code = {}
          k = 0
          jc.css('option').each do |jmc|
            k += 1
            next if k-1 == 0
            jmc_to_code[jmc.inner_text.strip] = jmc["value"]
            # puts "jmc name #{jmc.inner_text.strip} code: #{jmc_to_code[jmc.inner_text.strip]}"
          end
          jmc_to_code_arr << jmc_to_code.dup
        end
        j = 0

        dls.css('dd .job-category-selectfield option').each do |jc|
          j += 1
          next if j-1 == 0
          jc_to_jmc_to_code[jc.inner_text.strip] = jmc_to_code_arr[j-2]
          # puts "jc name #{jc.inner_text.strip} code: #{jc_to_jmc_to_code[jc.inner_text.strip]}"
        end
      end
      i += 1
    end
  end
end

csv_header = ['area',
              'sub_area',
              'job_genre',
              'sub_job_genre',
              'baito',
              'part',
              'haken',
              'job_title',
              'wage_max',
              'wage_min',
              'uni_student',
              'foreign_student',
              'shop_latitude',
              'shop_longitude']
# puts area_to_code
# puts jc_to_jmc_to_code
CSV.open('town_work_tokyo_from_setagaya_ku.csv', 'w') do |csv|
  csv << csv_header

  area_to_code.each do |area_name, area_code|
    next if area_name == "新宿区"
    next if area_name == "港区"
    next if area_name == "千代田区"
    next if area_name == "渋谷区"
    next if area_name == "豊島区"
    puts area_name
    jc_to_jmc_to_code.each do |jc_name, jmc_to_code|
      jmc_to_code.each do |jmc_name, jmc_code|
        {"大学生歓迎": "0004", "留学生歓迎": "0059"}.each do |prc_name, prc_code|
          url = "https://townwork.net/joSrchRsltList/?sac=#{area_code}&jmc=#{jmc_code}&emc=01&emc=06&emc=02&prc=#{prc_code}"
          count = 0
          begin
            doc = Nokogiri::HTML(open(url))
          rescue Errno::ECONNRESET => e
            count += 1
            retry unless count > 10
            puts "tried 10 times and couldn't get #{url}: #{e}"
          end
          num_articles = doc.css('.hit-num').inner_text.to_i
          next if num_articles == 0
          page_num = 1
          while true do
            page_num += 1
            num_articles_in_page = doc.css('.job-lst-main-cassette-wrap .job-lst-box-wrap > a').length
            article_num = 0
            doc.css('.job-lst-main-cassette-wrap .job-lst-box-wrap > a').each do |article| # 1 article
              article_num += 1
              part = false
              baito = false
              haken = false
              article.css('.job-lst-cassette-section-detail li').each do |job_type| # パート or アルバイト or 派遣社員
                case job_type.inner_text
                when "パート"
                  part = true
                when "アルバイト"
                  baito = true
                when "派遣社員"
                  haken = true
                end
              end
              job_title = article.css('.job-lst-main-txt-lnk').inner_text.strip
              salaries = article.css('.txt-salary.b').map{|salary_element| salary_element.inner_text.to_i}
              wage_min = salaries.min
              wage_max = salaries.max
              uni_student = false
              foreign_student = false
              should_add_to_csv = true
              if prc_name == "大学生歓迎".to_sym
                uni_student = true
                article.css('.job-lst-main-box-merit li').each do |merit| # Also check if they welcome 留学生
                  foreign_student = true if merit.inner_text == "留学生歓迎"
                end
              else
                foreign_student = true
                article.css('.job-lst-main-box-merit li').each do |merit|
                  should_add_to_csv = false if merit.inner_text == "大学生"# If the merit includes 大学生, this article will be checked when searching 大学生.
                end
              end
              url_2 = 'https://townwork.net' + article['href']
              count = 0
              begin
                shop_page = Nokogiri::HTML(open(url_2))
              rescue Errno::ECONNRESET => e
                count += 1
                retry unless count > 10
                puts "tried 10 times and couldn't get #{url}: #{e}"
              end

              map_element = shop_page.css('.ico-flag')[0]
              shop_latitude = map_element ? map_element['data-lat'].to_f : nil
              shop_longitude = map_element ? map_element['data-lon'].to_f : nil
              # puts "owatta"
              # [area,
              # sub_area,
              # job_genre,
              # sub_job_genre,
              # baito,
              # part,
              # haken,
              # job_title,
              # wage_max,
              # wage_min,
              # uni_student,
              # foreign_student,
              # shop_latitude,
              # shop_longitude]
              if should_add_to_csv
                csv << ["tokyo", area_name, jc_name, jmc_name, baito, part, haken,
                        job_title, wage_max, wage_min, uni_student, foreign_student,
                        shop_latitude, shop_longitude]
              end
            end
            num_articles -= num_articles_in_page
            if num_articles > 0
              count = 0
              begin
                doc = Nokogiri::HTML(open(url + "&page=#{page_num}"))
              rescue Errno::ECONNRESET => e
                count += 1
                retry unless count > 10
                puts "tried 10 times and couldn't get #{url + "&page=#{page_num}"}: #{e}"
              end
            else
              break
            end
          end
        end
      end
    end
  end
end
