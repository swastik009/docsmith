# frozen_string_literal: true

module Docsmith
  module Comments
    # Placeholder stub for Comment AR model.
    # The full implementation (validations, methods, scopes) comes in Task 3.2.
    # This minimal stub allows the association to work without NameError.
    class Comment < ActiveRecord::Base
      self.table_name = "docsmith_comments"
    end
  end
end
