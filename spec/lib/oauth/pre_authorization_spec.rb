# frozen_string_literal: true

require "spec_helper"

RSpec.describe Doorkeeper::OAuth::PreAuthorization do
  subject do
    described_class.new(server, attributes)
  end

  let(:server) do
    server = Doorkeeper.configuration
    allow(server).to receive(:default_scopes).and_return(Doorkeeper::OAuth::Scopes.from_string("default"))
    allow(server).to receive(:optional_scopes).and_return(Doorkeeper::OAuth::Scopes.from_string("public profile"))
    server
  end

  let(:application) { FactoryBot.create(:application, redirect_uri: "https://app.com/callback") }
  let(:client) { Doorkeeper::OAuth::Client.find(application.uid) }

  let :attributes do
    {
      client_id: client.uid,
      response_type: "code",
      redirect_uri: "https://app.com/callback",
      state: "save-this",
      current_resource_owner: Object.new,
    }
  end

  it "is authorizable when request is valid" do
    expect(subject).to be_authorizable
  end

  it "accepts code as response type" do
    attributes[:response_type] = "code"
    expect(subject).to be_authorizable
  end

  it "accepts token as response type" do
    allow(server).to receive(:grant_flows).and_return(["implicit"])
    attributes[:response_type] = "token"
    expect(subject).to be_authorizable
  end

  context "when using default grant flows" do
    it 'accepts "code" as response type' do
      attributes[:response_type] = "code"
      expect(subject).to be_authorizable
    end

    it 'accepts "token" as response type' do
      allow(server).to receive(:grant_flows).and_return(["implicit"])
      attributes[:response_type] = "token"
      expect(subject).to be_authorizable
    end
  end

  context "when authorization code grant flow is disabled" do
    before do
      allow(server).to receive(:grant_flows).and_return(["implicit"])
    end

    it 'does not accept "code" as response type' do
      attributes[:response_type] = "code"
      expect(subject).not_to be_authorizable
    end
  end

  context "when implicit grant flow is disabled" do
    before do
      allow(server).to receive(:grant_flows).and_return(["authorization_code"])
    end

    it 'does not accept "token" as response type' do
      attributes[:response_type] = "token"
      expect(subject).not_to be_authorizable
    end
  end

  context "when grant flow is client credentials & redirect_uri is nil" do
    before do
      allow(server).to receive(:grant_flows).and_return(["client_credentials"])
      allow(Doorkeeper.configuration).to receive(:allow_grant_flow_for_client?).and_return(false)
      application.update_column :redirect_uri, nil
    end

    it "is not authorizable" do
      expect(subject).not_to be_authorizable
    end
  end

  context "when client application does not restrict valid scopes" do
    it "accepts valid scopes" do
      attributes[:scope] = "public"
      expect(subject).to be_authorizable
    end

    it "rejects (globally) non-valid scopes" do
      attributes[:scope] = "invalid"
      expect(subject).not_to be_authorizable
    end

    it "accepts scopes which are permitted for grant_type" do
      allow(server).to receive(:scopes_by_grant_type).and_return(authorization_code: [:public])
      attributes[:scope] = "public"
      expect(subject).to be_authorizable
    end

    it "rejects scopes which are not permitted for grant_type" do
      allow(server).to receive(:scopes_by_grant_type).and_return(authorization_code: [:profile])
      attributes[:scope] = "public"
      expect(subject).not_to be_authorizable
    end
  end

  context "when client application restricts valid scopes" do
    let(:application) do
      FactoryBot.create(:application, scopes: Doorkeeper::OAuth::Scopes.from_string("public nonsense"))
    end

    it "accepts valid scopes" do
      attributes[:scope] = "public"
      expect(subject).to be_authorizable
    end

    it "rejects (globally) non-valid scopes" do
      attributes[:scope] = "invalid"
      expect(subject).not_to be_authorizable
    end

    it "rejects (application level) non-valid scopes" do
      attributes[:scope] = "profile"
      expect(subject).not_to be_authorizable
    end

    it "accepts scopes which are permitted for grant_type" do
      allow(server).to receive(:scopes_by_grant_type).and_return(authorization_code: [:public])
      attributes[:scope] = "public"
      expect(subject).to be_authorizable
    end

    it "rejects scopes which are not permitted for grant_type" do
      allow(server).to receive(:scopes_by_grant_type).and_return(authorization_code: [:profile])
      attributes[:scope] = "public"
      expect(subject).not_to be_authorizable
    end
  end

  context "when scope is not provided to pre_authorization" do
    before { attributes[:scope] = nil }

    context "when default scopes is provided" do
      it "uses default scopes" do
        allow(server).to receive(:default_scopes).and_return(Doorkeeper::OAuth::Scopes.from_string("default_scope"))
        expect(subject).to be_authorizable
        expect(subject.scope).to eq("default_scope")
        expect(subject.scopes).to eq(Doorkeeper::OAuth::Scopes.from_string("default_scope"))
      end
    end

    context "when default scopes is none" do
      it "not be authorizable when none default scope" do
        allow(server).to receive(:default_scopes).and_return(Doorkeeper::OAuth::Scopes.new)
        expect(subject).not_to be_authorizable
      end
    end
  end

  it "matches the redirect uri against client's one" do
    attributes[:redirect_uri] = "http://nothesame.com"
    expect(subject).not_to be_authorizable
  end

  it "stores the state" do
    expect(subject.state).to eq("save-this")
  end

  it "rejects if response type is not allowed" do
    attributes[:response_type] = "whops"
    expect(subject).not_to be_authorizable
  end

  it "requires an existing client" do
    attributes[:client_id] = nil
    expect(subject).not_to be_authorizable
  end

  it "requires a redirect uri" do
    attributes[:redirect_uri] = nil
    expect(subject).not_to be_authorizable
  end

  context "when resource_owner cannot access client application" do
    before { allow(Doorkeeper.configuration).to receive(:authorize_resource_owner_for_client).and_return(->(*_) { false }) }

    it "is not authorizable" do
      expect(subject).not_to be_authorizable
    end
  end

  describe "as_json" do
    before { subject.authorizable? }

    it { is_expected.to respond_to :as_json }

    shared_examples "returns the pre authorization" do
      it "returns the pre authorization" do
        expect(json[:client_id]).to eq client.uid
        expect(json[:redirect_uri]).to eq subject.redirect_uri
        expect(json[:state]).to eq subject.state
        expect(json[:response_type]).to eq subject.response_type
        expect(json[:scope]).to eq subject.scope
        expect(json[:client_name]).to eq client.name
        expect(json[:status]).to eq I18n.t("doorkeeper.pre_authorization.status")
      end
    end

    context "when called without params" do
      let(:json) { subject.as_json }

      include_examples "returns the pre authorization"
    end

    context "when called with params" do
      let(:json) { subject.as_json(foo: "bar") }

      include_examples "returns the pre authorization"
    end
  end
end
