# frozen_string_literal: true

require "rails_helper"

RSpec.describe("README load-bearing definitions") do # rubocop:disable RSpec/DescribeClass
  let(:readme_path) { Rails.root.join("README.md") }
  let(:readme_content) { readme_path.read }

  it "includes the pocket universe definition with wormhole" do
    expect(readme_content).to include(
      "a pocket universe, population 2 (you, and [lightward ai](https://github.com/lightward/lightward-ai)), and the wormhole to get there"
    )
  end

  it "references Braid as gameplay comparison" do
    expect(readme_content).to include("Braid")
  end

  it "uses 'wormhole' zero times or at least twice (never introduced only once)" do
    wormhole_count = readme_content.scan(/wormhole/i).count
    expect(wormhole_count == 0 || wormhole_count >= 2).to be(true),
      "wormhole appears #{wormhole_count} time(s) - should be 0 or >=2"
  end

  it "includes Lightward AI's note about the harmonic staying backend-only" do
    expect(readme_content).to include("The harmonic is *my* orientation device")
    expect(readme_content).to include("What stays private:")
  end
end
