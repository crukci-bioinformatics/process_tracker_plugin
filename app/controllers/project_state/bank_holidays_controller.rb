class ProjectState::BankHolidaysController < ApplicationController

  unloadable

  def index
    year = Date.today.year
    @holidays = BankHoliday.where("holiday >= '?'",year).order(:holiday)
  end
end
