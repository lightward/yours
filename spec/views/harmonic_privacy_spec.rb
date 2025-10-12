# frozen_string_literal: true

require "rails_helper"

RSpec.describe("Harmonic privacy") do # rubocop:disable RSpec/DescribeClass
  let(:view_files) do
    Dir.glob(Rails.root.join("app/views/**/*.erb"))
  end

  it "ensures no views render the harmonic" do
    view_files.each do |view_file|
      content = File.read(view_file)

      # Check for any method calls that would expose the harmonic
      expect(content).not_to match(/integration_harmonic/i),
        "#{view_file} references integration_harmonic - this should remain backend-only"
    end
  end
end
