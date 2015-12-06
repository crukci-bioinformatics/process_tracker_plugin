require 'simple_xlsx_reader'

class FinanceSheet

  @@funding_tag = "Funding Source"
  @@costcode_tag = "Cost Code"
  @@bioinf_tag = "CRUK Core Award: Research Groups"
  @@location = Struct.new(:row,:col)

  def initialize(filename)
    @doc = SimpleXlsxReader.open(filename)
  end

  def retrieve(year,month)
    get_sheet(year,month)
    src = funding_col
    cod = costcode_col
    start = start_row
    source = []
    code = []
    (start..(@data.length-1)).each do |i|
      row = @data[i]
#      source << row[src].nil? ? nil : row[src].strip
#      code << row[cod].nil? ? nil : row[cod].strip
      source << row[src]
      code << row[cod]
    end
    return [source,code]
  end

  private

  def get_sheet(year,month)
    $pslog.debug("Year: #{year}")
    $pslog.debug("Month: #{month}")
    tag = "#{month.capitalize}-#{year}"
    results = @doc.sheets.select{|s| s.name == tag}
    if results.length != 1
      # length can't be > 1, sheet names must be unique
      raise NameError, "sheet #{tag} not found"
    end
    @sheet = results[0]
    @data = @sheet.data
  end

  def find_cell(tag)
    found = false
    crow = nil
    ccol = nil
    @data.each_with_index do |row,rnum|
      row.each_with_index do |cell,cnum|
        if cell == tag
          found = true
          crow = rnum
          ccol = cnum
          break
        end
      end
      break if found
    end
    return @@location.new(crow,ccol)
  end
    
  def funding_col
    return find_cell(@@funding_tag).col
  end

  def costcode_col
    return find_cell(@@costcode_tag).col
  end

  def start_row
    return find_cell(@@bioinf_tag).row + 1
  end

end
