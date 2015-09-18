class TimeLimitDefault < ActiveRecord::Base
  unloadable

  belongs_to :tracker

end
