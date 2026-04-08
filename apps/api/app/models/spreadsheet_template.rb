# frozen_string_literal: true

SpreadsheetTemplate = Data.define(:sheets)
SpreadsheetTemplate::Sheet = Data.define(:name, :headers)
