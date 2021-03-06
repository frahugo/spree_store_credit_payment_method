require 'spec_helper'

describe "StoreCreditEvent" do
  describe "#display_amount" do
    let(:event_amount) { 120.0 }

    subject { create(:store_credit_auth_event, amount: event_amount) }

    it "returns a Spree::Money instance" do
      subject.display_amount.should be_instance_of(Spree::Money)
    end

    it "uses the events amount attribute" do
      subject.display_amount.should eq Spree::Money.new(event_amount, { currency: subject.currency })
    end
  end

  describe "#display_user_total_amount" do
    let(:user_total_amount) { 300.0 }

    subject { create(:store_credit_auth_event, user_total_amount: user_total_amount) }

    it "returns a Spree::Money instance" do
      subject.display_user_total_amount.should be_instance_of(Spree::Money)
    end

    it "uses the events user_total_amount attribute" do
      subject.display_user_total_amount.should eq Spree::Money.new(user_total_amount, { currency: subject.currency })
    end
  end

  describe "#display_event_date" do
    let(:date) { DateTime.new(2014, 06, 1) }

    subject { create(:store_credit_auth_event, created_at: date) }

    it "returns the date the event was created with the format month/date/year" do
      subject.display_event_date.should eq "06/01/2014"
    end
  end

  describe "#display_action" do
    subject { create(:store_credit_auth_event, action: action) }

    context "capture event" do
      let(:action) { Spree::StoreCredit::CAPTURE_ACTION }

      it "returns used" do
        subject.display_action.should eq Spree.t('store_credit.captured')
      end
    end

    context "authorize event" do
      let(:action) { Spree::StoreCredit::AUTHORIZE_ACTION }

      it "returns authorized" do
        subject.display_action.should eq Spree.t('store_credit.authorized')
      end
    end

    context "allocation event" do
      let(:action) { Spree::StoreCredit::ALLOCATION_ACTION }

      it "returns added" do
        subject.display_action.should eq Spree.t('store_credit.allocated')
      end
    end

    context "void event" do
      let(:action) { Spree::StoreCredit::VOID_ACTION }

      it "returns credit" do
        subject.display_action.should eq Spree.t('store_credit.credit')
      end
    end

    context "credit event" do
      let(:action) { Spree::StoreCredit::CREDIT_ACTION }

      it "returns credit" do
        subject.display_action.should eq Spree.t('store_credit.credit')
      end
    end
  end

  describe "#order" do
    context "there is no associated payment with the event" do
      subject { create(:store_credit_auth_event) }

      it "returns nil" do
        subject.order.should be_nil
      end
    end

    context "there is an associated payment with the event" do
      let(:authorization_code) { "1-SC-TEST" }
      let(:order)              { create(:order) }
      let!(:payment)           { create(:store_credit_payment, order: order, response_code: authorization_code) }

      subject { create(:store_credit_auth_event, action: Spree::StoreCredit::CAPTURE_ACTION, authorization_code: authorization_code) }

      it "returns the order associated with the payment" do
        subject.order.should eq order
      end
    end
  end
end
