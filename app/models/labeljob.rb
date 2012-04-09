class Labeljob < ActiveRecord::Base
  validates :name, :presence => true,
    :length => { :maximum => 30 }
  validates :desc, :presence => true,
    :length => { :maximum => 3000 }
  #validates :rawdata, :presence => true
  label_regex = /([^\|]*\|)*/
  validates :labels,  :format => { :with => label_regex }
  attr_readonly :labels,:user_ids,:rawdata

  has_many :labeltasks, :dependent => :destroy
  belongs_to :user
  # has_many :joblabellers, :dependent => :destroy
  # has_many :labellers, :through => :joblabellers,
  #                      :source => :labeller
  has_and_belongs_to_many :users
  # after_save :generate_tasks
  after_create :generate_tasks
  mount_uploader :rawdata, RawdataUploader
  mount_uploader :filter, FilterUploader

  def word_label?
    self.labels.blank?
  end

  def classic?
    not word_label?
  end

  def finished?
    self.finished 
  end

  #def label_numbers
  #  self.labels.split('|').length
  #end
  
  def finish!
    self.update_attributes(:finished => true)
    self.labeltasks.each do |task|
      task.approve!
    end
    self.save!
  end

  def generate_tasks
    # first , delete all the old tasks
    self.labeltasks.each { |task| task.destroy } if self.labeltasks !=nil
    data = self.rawdata.read.split(/\n/).delete_if { |i| i == "" }

    if self.word_label? && !self.filter.url.nil?
      #filtrate the rawdata
      self.filter.read.split(/\n/).delete_if { |i| i == "" }.each do |filter|
        data.delete_if { |item| item.include?(filter) }
      end
    end

    length           = data.length
    labellers        = self.users
    labeller_numbers = labellers.length
    tasksize         = length / labeller_numbers
    remainder        = length % labeller_numbers

    i       = 0
    start   = 0

    while i < remainder
      create_task(i, start, tasksize, data) 
      start = start + tasksize + 1
      i += 1
    end

    while i < labeller_numbers && i < length
      create_task(i, start, tasksize, data) 
      start = start + tasksize
      i += 1
    end
  end

  def create_task(i, start, tasksize, data)
    self.labeltasks.create!(:status => "assigned",
                            :user_id => self.users[i].id)
    labeltask = self.labeltasks.where(:user_id => self.users[i].id).first

    data[start..(start + tasksize - 1)].each_with_index do |line, line_number|
      labeltask.solutions.create!(:line_number => line_number,
                                  :rawdata => line,
                                  :label => "unknown")
    end   
  end

  def label_all(word)
    self.labeltasks.each do |task|
      task.solutions.where("label = 'unknown' AND rawdata LIKE '%#{word}%'").update_all "label = '#{word}'"
    end
  end

  def delete_all(word)
    self.labeltasks.each do |task|
      task.solutions.where(:label => word).update_all(:label => "unknown")
    end
  end

end
