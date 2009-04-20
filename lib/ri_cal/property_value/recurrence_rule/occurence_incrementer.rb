module RiCal
  class PropertyValue
    class RecurrenceRule < PropertyValue
      module RangePredicates
        def same_year?(old_date_time, new_date_time)
          old_date_time.year == new_date_time.year
        end

        def same_month?(old_date_time, new_date_time)
          (old_date_time.month == new_date_time.month) && same_year?(old_date_time, new_date_time)
        end

        def same_week?(wkst, old_date_time, new_date_time)
          diff = (new_date_time.to_datetime - (old_date_time.at_start_of_week_with_wkst(wkst).to_datetime))
          diff.between?(0,6)
        end

        def same_day?(old_date_time, new_date_time)
          (old_date_time.day == new_date_time.day) && same_month?(old_date_time, new_date_time)
        end

        def same_hour?(old_date_time, new_date_time)
          (old_date_time.hour == new_date_time.hour) && same_day?(old_date_time, new_date_time)
        end

        def same_minute?(old_date_time, new_date_time)
          (old_date_time.min == new_date_time.min) && same_hour?(old_date_time, new_date_time)
        end

        def same_second?(old_date_time, new_date_time)
          (old_date_time.second == new_date_time.second) && same_minute?(old_date_time, new_date_time)
        end
      end

      module TimeManipulation

        def top_of_hour(date_time)
          date_time.change(:minute => 0)
        end

        def advance_day(date_time)
          date_time.advance(:days => 1)
        end

        def first_hour_of_day(date_time)
          date_time.change(:hour => 0)
        end

        def advance_week(date_time)
          date_time.advance(:days => 7)
        end

        def first_day_of_week(wkst_day, date_time)
          date_time.at_start_of_week_with_wkst(wkst_day)
        end

        def advance_month(date_time)
          date_time.advance(:months => 1)
        end

        def first_day_of_month(date_time)
          date_time.change(:day => 1)
        end

        def advance_year(date_time)
          date_time.advance(:years => 1)
        end

        def first_day_of_year(date_time)
          date_time.change(:month => 1, :day => 1)
        end

        def first_month_of_year(date_time)
          date_time.change(:month => 1)
        end
      end

      class OccurrenceIncrementer # :nodoc:

        attr_accessor :sub_cycle_incrementer, :current_occurrence, :outer_range
        attr_accessor :outer_incrementers
        attr_accessor :contains_daily_incrementer
        attr_reader :leaf_iterator

        include RangePredicates
        include TimeManipulation

        class NullSubCycleIncrementer
          def self.next_time(previous)
            nil
          end

          def self.add_outer_incrementer(incrementer)
          end

          def self.first_within_outer_cycle(previous_occurrence, outer_cycle_range)
            outer_cycle_range.first
          end

          def self.first_sub_occurrence(previous_occurrence, outer_cycle_range)
            nil
          end

          def self.cycle_adjust(date_time)
            date_time
          end

          def self.list?
            false
          end

          def self.to_s
            "NULL-INCR"
          end

          def inspect
            to_s
          end
        end

        def initialize(rrule, sub_cycle_incrementer)
          self.sub_cycle_incrementer = sub_cycle_incrementer
          @outermost = true
          self.outer_incrementers = []
          if sub_cycle_incrementer
            self.contains_daily_incrementer = sub_cycle_incrementer.daily_incrementer? ||
            sub_cycle_incrementer.contains_daily_incrementer?
            sub_cycle_incrementer.add_outer_incrementer(self)
          else
            self.sub_cycle_incrementer = NullSubCycleIncrementer
          end
        end

        def add_outer_incrementer(incrementer)
          @outermost = false
          self.outer_incrementers << incrementer
          sub_cycle_incrementer.add_outer_incrementer(incrementer)
        end

        def outermost?
          @outermost
        end

        def to_s
          if sub_cycle_incrementer
            "#{self.short_name}->#{sub_cycle_incrementer}"
          else
            self.short_name
          end
        end

        def short_name
          @short_name ||= self.class.name.split("::").last
        end

        # Return the next time after previous_occurrence generated by this incrementer
        # But the occurrence is outside the current cycle of any outer incrementer(s) return
        # nil which will cause the outer incrementer to step to its next cycle.
        def next_time(previous_occurrence)
          rputs "#{self.short_name}.next_time(#{previous_occurrence})"
          if current_occurrence
            sub_occurrence = sub_cycle_incrementer.next_time(previous_occurrence)
          else #first time
            sub_occurrence = sub_cycle_incrementer.first_sub_occurrence(previous_occurrence, update_cycle_range(previous_occurrence))
          end
          rputs "  #{short_name}.next_time - sub_occurrence is #{sub_occurrence}"
          if sub_occurrence
            candidate = sub_occurrence
          else
            candidate = next_cycle(previous_occurrence)
            rputs "  #{short_name}.next_time no sub_occurrence candidate now #{candidate}"
          end
          if in_outer_cycle?(candidate)
            rputs "#{short_name}.next_time returning #{candidate} \n  #{caller[0,3].join("  \n")}"
            candidate
          else
            rputs "  #{short_name}.next_time #{candidate} was rejected"
            nil
          end
        end

        def update_cycle_range(date_time)
          self.current_occurrence = date_time
          (date_time..end_of_occurrence(date_time))
        end

        def in_outer_cycle?(candidate)
          rputs "#{short_name}.in_outer_cycle?(#{candidate}) outer_range is #{outer_range.inspect}"
          candidate && (outer_range.nil? || outer_range.include?(candidate))
        end

        def first_sub_occurrence(previous_occurrence, outer_cycle_range)
          first_within_outer_cycle(previous_occurrence, outer_cycle_range)
        end

        def first_occurrence_of_cycle(previous_occurrence, start_of_cycle)
          rputs "#{short_name}.first_occurrence_of_cycle(#{previous_occurrence}, #{start_of_cycle})"
          self.current_occurrence = sub_cycle_incrementer.adjust_outer_cycle_start(start_of_cycle)
        end

        # Advance to the next cycle, if the result is within the current cycles of all outer incrementers
        def next_cycle(previous_occurrence)
          raise "next_cycle is a subclass responsibility"
        end

        def contains_daily_incrementer?
          @contains_daily_incrementer
        end

        def daily_incrementer?
          false
        end

        def adjust_outer_cycle_start(start_of_cycle)
          rputs "#{short_name}.adjust_outer_cycle_start(#{start_of_cycle}) no change!"
          start_of_cycle
        end
      end

      # A ListIncrementer represents a byxxx part of a recurrence rule
      # It contains a list of simple values or recurring values
      # It keeps a collection of occurrences within a given range called a cycle
      # When the collection of occurrences is exhausted it is refreshed if there is no
      # outer incrementer, or if a new cycle would start in the current cycle of the outer incrementers.
      class ListIncrementer < OccurrenceIncrementer
        attr_accessor :occurrences, :list, :outer_occurrence, :cycle_start

        def initialize(rrule, list, sub_cycle_incrementer)
          super(rrule, sub_cycle_incrementer)
          self.list = list
        end

        def self.conditional_incrementer(rrule, by_part, sub_cycle_class)
          sub_cycle_incrementer = sub_cycle_class.for_rrule(rrule)
          list = rrule.by_rule_list(by_part)
          if list
            new(rrule, list, sub_cycle_incrementer)
          else
            sub_cycle_incrementer
          end
        end

        def list?
          true
        end

        # Advance to the next occurrence, if the result is within the current cycles of all outer incrementers
        def next_cycle(previous_occurrence)
          rputs "#{short_name}.next_cycle(#{previous_occurrence})"
          unless occurrences
            self.occurrences = occurrences_for(previous_occurrence)
          end
          candidate = next_candidate(previous_occurrence)
          rputs "  candidate is #{candidate}"
          if candidate
            sub_cycle_incrementer.first_within_outer_cycle(previous_occurrence, update_cycle_range(candidate))
          else
            nil
          end
        end

        def first_within_outer_cycle(previous_occurrence, outer_range)
          rputs "#{short_name}.first_within_outer_cycle(#{previous_occurrence}, #{outer_range})"
          self.outer_range = outer_range
          self.occurrences = occurrences_within(outer_range)
          occurrences.each { |occurrence|
            sub = sub_cycle_incrementer.first_within_outer_cycle(previous_occurrence, update_cycle_range(occurrence))
            return sub if sub && sub > previous_occurrence
            }
          nil
          # if (target = outer_range.first) > previous_occurrence
          #   rputs "  looking for #{target}"
          #   first_occurrence = occurrences.find {|occurrence| 
          #       occurrence >= target ||
          #      (occurrence..end_of_occurrence(occurrence)).include?(target)
          #     }
          # else
          #   rputs "  looking for previous_occurrence #{previous_occurrence}"
          #   first_occurrence = occurrences.find {|occurrence| 
          #       occurrence > previous_occurrence
          #     }
          # end
          # if first_occurrence
          #             sub_cycle_incrementer.first_within_outer_cycle(previous_occurrence, update_cycle_range(first_occurrence))
          #           else
          #             nil
          #           end
        end

        def next_candidate(date_time)
          candidate = next_in_list(date_time)
          rputs "#{short_name}.next_candidate(#{date_time}) first_candidate is #{candidate}"
          if outermost?
            while candidate.nil?
              get_next_occurrences
              candidate = next_in_list(date_time)
            end
          end
          candidate
        end

        def next_in_list(date_time)
          occurrences.find {|occurrence| occurrence > date_time}
        end

        def get_next_occurrences
          rputs "#{short_name}.get_next_occurrences"
          rputs "  occurrences were #{occurrences.inspect}"
          adv_cycle = advance_cycle(start_of_cycle(occurrences.first))
          rputs "  new cycle starts with #{adv_cycle}"
          self.occurrences = occurrences_for(adv_cycle)
          rputs "  occurrences now  #{occurrences.inspect}"
        end
        
        def cycle_adjust(date_time)
          sub_cycle_incrementer.cycle_adjust(start_of_cycle(date_time))
        end

        # Don't let the time being searched for to go backwards
        def ratchet(previous_occurrence)
          if current_occurrence && current_occurrence > previous_occurrence
            current_occurrence
          else
            previous_occurrence
          end
        end

        def occurrences_for(date_time)
          list.map {|value| date_time.change(varying_time_attribute => value)}
        end

        def occurrences_within(date_time_range)
          result = []
          rputs "#{short_name}.occurrences_within(#{date_time_range})"
          date_time = date_time_range.first
          rputs "  first date_time is #{date_time}"
          while date_time <= date_time_range.last
             result << occurrences_for(date_time)
             rputs " result now #{result.inspect}"
             date_time = advance_cycle(date_time)
             rputs " date_time now #{date_time}"
           end
           rputs "returning #{result.flatten.inspect}"
           result.flatten
        end
      end

      # A FrequenceIncrementer represents the xxxLY and FREQ parts of a recurrence rule
      # A FrequenceIncrementer has a single occurrence within each cycle.
      class FrequencyIncrementer < OccurrenceIncrementer
        attr_accessor :interval, :outer_occurrence, :skip_increment

        alias_method :cycle_start, :current_occurrence

        def initialize(rrule, sub_cycle_incrementer)
          super(rrule, sub_cycle_incrementer)
          self.interval = rrule.interval
        end

        def list?
          false
        end

        def self.conditional_incrementer(rrule, freq_str, sub_cycle_class)
          sub_cycle_incrementer = sub_cycle_class.for_rrule(rrule)
          if rrule.freq == freq_str
            new(rrule, sub_cycle_incrementer)
          else
            sub_cycle_incrementer
          end
        end

        def multiplier
          1
        end

        def step(occurrence)
          occurrence.advance(advance_what => (interval * multiplier))
        end

        def first_within_outer_cycle(previous_occurrence, outer_cycle_range)
          rputs "#{short_name}.first_within_outer_cycle(#{previous_occurrence}, #{outer_range})"
          if outer_range
            first_occurrence = outer_cycle_range.first
          else
            first_occurrence = step(previous_occurrence)
          end
          self.outer_range = outer_cycle_range
          sub_cycle_incrementer.first_within_outer_cycle(previous_occurrence, update_cycle_range(first_occurrence))
        end

        # Advance to the next occurrence, if the result is within the current cycles of all outer incrementers
        def next_cycle(previous_occurrence)
          rputs "#{short_name}.next_cycle(#{previous_occurrence}) current_occurrence is #{current_occurrence}"
          if current_occurrence
            candidate = sub_cycle_incrementer.cycle_adjust(step(current_occurrence))
          else
            candidate = step(previous_occurrence)
          end
          rputs " #{short_name}.next_cycle candidate is #{candidate}"
          if in_outer_cycle?(candidate)
            sub_cycle_incrementer.first_within_outer_cycle(previous_occurrence, update_cycle_range(candidate))
          else
            rputs "#{short_name}.next_cycle candidate was rejected"
            nil
          end
        end

        def cycle_adjust(date_time)
          sub_cycle_incrementer.cycle_adjust(date_time)
        end
      end

      class SecondlyIncrementer < FrequencyIncrementer

        def self.for_rrule(rrule)
          if rrule.freq == "SECONDLY"
            new(rrule, nil)
          else
            nil
          end
        end

        def advance_what
          :seconds
        end

        def end_of_occurrence(date_time)
          date_time
        end
      end


      class BySecondIncrementer < ListIncrementer

        def self.for_rrule(rrule)
          conditional_incrementer(rrule, :bysecond, SecondlyIncrementer)
        end

        def current?(date_time)
          false
        end

        def varying_time_attribute
          :sec
        end

        def start_of_cycle(date_time)
          date_time.start_of_minute
        end

        def advance_cycle(date_time)
          date_time.advance(:minutes => 1).start_of_minute
        end

        def end_of_occurrence(date_time)
          date_time
        end
      end

      class MinutelyIncrementer < FrequencyIncrementer
        def self.for_rrule(rrule)
          conditional_incrementer(rrule, "MINUTELY", BySecondIncrementer)
        end


        def current?(date_time)
          same_minute?(current_occurrence, date_time)
        end

        def advance_what
          :minutes
        end

        def end_of_occurrence(date_time)
          date_time.end_of_minute
        end
      end

      class ByMinuteIncrementer < ListIncrementer
        def self.for_rrule(rrule)
          conditional_incrementer(rrule, :byminute, MinutelyIncrementer)
        end

        def current?(date_time)
          same_minute?(current_occurrence, date_time)
        end

        def advance_cycle(date_time)
          date_time.advance(:hours => 1).start_of_hour
        end

        def start_of_cycle(date_time)
          date_time.change(:min => 0)
        end

        def end_of_occurrence(date_time)
          date_time.end_of_minute
        end

        def varying_time_attribute
          :min
        end
      end

      class HourlyIncrementer < FrequencyIncrementer
        def self.for_rrule(rrule)
          conditional_incrementer(rrule, "HOURLY", ByMinuteIncrementer)
        end


        def current?(date_time)
          same_hour?(current_occurrence, date_time)
        end

        def advance_what
          :hours
        end

        def end_of_occurrence(date_time)
          date_time.end_of_hour
        end
      end


      class ByHourIncrementer < ListIncrementer
        def self.for_rrule(rrule)
          conditional_incrementer(rrule, :byhour, HourlyIncrementer)
        end

        def current?(date_time)
          same_hour?(cycle_start, date_time)
        end

        def range_advance(date_time)
          advance_day(date_time)
        end

        def start_of_cycle(date_time)
          date_time.change(:hour => 1)
        end

        def varying_time_attribute
          :hour
        end

        def advance_cycle(date_time)
          first_hour_of_day(advance_day(date_time))
        end

        def end_of_occurrence(date_time)
          date_time.end_of_hour
        end
      end

      class DailyIncrementer < FrequencyIncrementer

        def self.for_rrule(rrule)
          conditional_incrementer(rrule, "DAILY", ByHourIncrementer)
        end

        def daily_incrementer?
          true
        end

        def current?(date_time)
          same_day?(current_occurrence, date_time)
        end

        def advance_what
          :days
        end

        def end_of_occurrence(date_time)
          date_time.end_of_day
        end
      end

      class ByNumberedDayIncrementer < ListIncrementer

        def daily_incrementer?
          true
        end

        def current?(date_time)
          scope_of(current_occurrence)== scope_of(date_time)
        end

        def occurrences_for(date_time)
          if occurrences && @scoping_value == scope_of(date_time)
             occurrences
          else
            @scoping_value = scope_of(date_time)
            self.occurrences = list.map {|numbered_day| numbered_day.target_date_time_for(date_time)}.uniq.sort
            occurrences
          end
        end

        def end_of_occurrence(date_time)
          date_time.end_of_day
        end

        def candidate_acceptible?(candidate)
          list.any? {|by_part| by_part.include?(candidate)}
        end
      end
      class ByDayIncrementer < ListIncrementer

        def initialize(rrule, list, parent)
          super(rrule, list, parent)
          case rrule.by_day_scope
          when :yearly
            @cycle_advance_proc = lambda {|date_time| first_day_of_year(advance_year(date_time))}
            @current_proc = lambda {|date_time| same_year?(current, date_time)}
            @first_day_proc = lambda {|date_time| first_day_of_year(date_time)}
          when :monthly
            @cycle_advance_proc = lambda {|date_time| first_day_of_month(advance_month(date_time))}
            @current_proc = lambda {|date_time| same_month?(current, date_time)}
            @first_day_proc = lambda {|date_time| first_day_of_month(date_time)}
          when :weekly
            @cycle_advance_proc = lambda {|date_time| first_day_of_week(rrule.wkst_day, advance_week(date_time))}
            @current_proc = lambda {|date_time| same_week?(rrule.wkst_day, current, date_time)}
            @first_day_proc = lambda {|date_time| first_day_of_week(rrule.wkst_day, date_time)}
          else
            raise "Invalid recurrence rule, byday needs to be scoped by month, week or year"
          end
        end

        def self.for_rrule(rrule)
          conditional_incrementer(rrule, :byday, DailyIncrementer)
        end

        def daily_incrementer?
          true
        end

        def start_of_cycle(date_time)
          @first_day_proc.call(date_time)
        end

        def occurrences_for(date_time)
          first_day = start_of_cycle(date_time)
          result = list.map {|recurring_day| recurring_day.matches_for(first_day)}.flatten.uniq.sort
          result
        end

        def candidate_acceptible?(candidate)
          list.any? {|recurring_day| recurring_day.include?(candidate)}
        end

        def current?(date_time)
          @current_proc.call(date_time)
        end

        def varying_time_attribute
          :day
        end

        def advance_cycle(date_time)
          @cycle_advance_proc.call(date_time)
        end

        def end_of_occurrence(date_time)
          date_time.end_of_day
        end
      end


      class ByMonthdayIncrementer < ByNumberedDayIncrementer
        def self.for_rrule(rrule)
          conditional_incrementer(rrule, :bymonthday, ByDayIncrementer)
        end

        def scope_of(date_time)
          date_time.month
        end

        def range_advance(date_time)
          advance_month(date_time)
        end

        def start_of_cycle(date_time)
          date_time.change(:day => 1)
        end

        def advance_cycle(date_time)
          first_day_of_month(advance_month(date_time))
        end

        def end_of_occurrence(date_time)
          date_time.end_of_day
        end
      end

      class ByYeardayIncrementer < ByNumberedDayIncrementer
        def self.for_rrule(rrule)
          conditional_incrementer(rrule, :byyearday, ByMonthdayIncrementer)
        end

        def range_advance(date_time)
          advance_year(date_time)
        end

        def start_of_cycle(date_time)
          date_time.change(:month => 1, :day => 1)
        end

        def scope_of(date_time)
          date_time.year
        end

        def advance_cycle(date_time)
          first_day_of_year(advance_year(date_time))
        end

        def end_of_occurrence(date_time)
          date_time.end_of_day
        end
      end

      class WeeklyIncrementer < FrequencyIncrementer

        attr_reader :wkst

        # include WeeklyBydayMethods

        def initialize(rrule, parent)
          @wkst = rrule.wkst_day
          super(rrule, parent)
        end

        def self.for_rrule(rrule)
          conditional_incrementer(rrule, "WEEKLY", ByYeardayIncrementer)
        end

        def current?(date_time)
          same_week?(wkst, current_occurrence, date_time)
        end

        def multiplier
          7
        end

        def advance_what
          :days
        end

        def end_of_occurrence(date_time)
          date_time.end_of_week_with_wkst(wkst)
        end
      end

      class ByWeekNoIncrementer < ListIncrementer
        attr_reader :wkst
        # include WeeklyBydayMethods

        def initialize(list, wkst, rrule, parent)
          super(rrule, list, parent)
          @wkst = wkst
        end

        def self.for_rrule(rrule)
          conditional_incrementer(rrule, :byweekno, WeeklyIncrementer)
        end

        def current?(date_time)
          same_month?(current_occurrence, date_time)
        end

        def range_advance(date_time)
          advance_year(date_time)
        end

        def start_of_cycle(date_time)
          first_day_of_year(date_time)
        end

        def occurrences_for(date_time)
          iso_year, week_one_start = *date_time.iso_year_and_week_one_start(wkst)
          weeks_in_year_plus_one = date_time.iso_weeks_in_year(wkst)
          weeks = list.map {|wk_num| (wk_num > 0) ? wk_num : weeks_in_year_plus_one + wk_num}.uniq.sort
          weeks.map {|wk_num| week_one_start.advance(:days => (wk_num - 1) * 7)}
        end

        def candidate_acceptible?(candidate)
          list.include?(candidate.iso_week_num(wkst))
        end

        def advance_cycle(date_time)
          first_day_of_year(advance_year(date_time))
        end

        def end_of_occurrence(date_time)
          date_time.end_of_week_with_wkst(wkst)
        end
      end

      class MonthlyIncrementer < FrequencyIncrementer

        def self.for_rrule(rrule)
          conditional_incrementer(rrule, "MONTHLY", ByWeekNoIncrementer)
        end

        def current?(date_time)
          same_month?(current_occurrence, date_time)
        end

        def advance_what
          :months
        end

        def end_of_occurrence(date_time)
          date_time.end_of_month
        end
      end

      class ByMonthIncrementer < ListIncrementer

        def self.for_rrule(rrule)
          conditional_incrementer(rrule, :bymonth, MonthlyIncrementer)
        end

        def current?(date_time)
          same_month?(current_occurrence, date_time)
        end

        def occurrences_for(date_time)
          if contains_daily_incrementer?
            list.map {|value| date_time.change(:month => value, :day => 1)}
          else
            list.map {|value| date_time.in_month(value)}
          end
        end

        def range_advance(date_time)
          advance_year(date_time)
        end

        def start_of_cycle(date_time)
          if contains_daily_incrementer?
            date_time.change(:month => 1, :day => 1)
          else
            date_time.change(:month => 1)
          end
        end

        def varying_time_attribute
          :month
        end

        def advance_cycle(date_time)
          if contains_daily_incrementer?
            first_day_of_year(advance_year(date_time))
          else
            advance_year(date_time).change(:month => 1)
          end
        end

        def end_of_occurrence(date_time)
          date_time.end_of_month
        end
      end

      class YearlyIncrementer < FrequencyIncrementer

        def self.from_rrule(rrule, start_time)
          conditional_incrementer(rrule, "YEARLY", ByMonthIncrementer)
        end

        def current?(date_time)
          same_year?(current_occurrence, date_time)
        end

        def advance_what
          :years
        end

        def start_of_cycle(date_time)
          if contains_daily_incrementer?
            date_time.change(:month => 1, :day => 1)
          else
            date_time.change(:month => 1)
          end
        end

        def end_of_occurrence(date_time)
          date_time.end_of_year
        end
     end
    end
  end
end
