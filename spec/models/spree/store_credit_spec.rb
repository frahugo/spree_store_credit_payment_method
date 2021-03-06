require 'spec_helper'

describe "StoreCredit" do

  let(:currency) { "TEST" }
  let(:store_credit) { build(:store_credit, store_credit_attrs) }
  let(:store_credit_attrs) { {} }


  describe "callbacks" do
    subject { store_credit.save }

    context "amount used is greater than zero" do
      let(:store_credit) { create(:store_credit, amount: 100, amount_used: 1) }
      subject { store_credit.destroy }

      it 'can not delete the store credit' do
        subject
        store_credit.reload.should eq store_credit
        store_credit.errors[:amount_used].should include(Spree.t('admin.store_credits.errors.amount_used_not_zero'))
      end
    end

    context "category is a non-expiring type" do
      let!(:secondary_credit_type) { create(:secondary_credit_type) }
      let(:store_credit) { build(:store_credit, credit_type: nil)}

      before do
        store_credit.category.stub(:non_expiring?).and_return(true)
      end

      it "sets the credit type to non-expiring" do
        subject
        store_credit.credit_type.name.should eq secondary_credit_type.name
      end
    end

    context "category is an expiring type" do
      before do
        store_credit.category.stub(:non_expiring?).and_return(false)
      end

      it "sets the credit type to non-expiring" do
        subject
        store_credit.credit_type.name.should eq "Expiring"
      end
    end

    context "the type is set" do
      let!(:secondary_credit_type) { create(:secondary_credit_type)}
      let(:store_credit) { build(:store_credit, credit_type: secondary_credit_type)}

      before do
        store_credit.category.stub(:non_expiring?).and_return(false)
      end

      it "doesn't overwrite the type" do
        expect{ subject }.to_not change{ store_credit.credit_type }
      end
    end
  end

  describe "validations" do
    describe "used amount should not be greater than the credited amount" do
      context "the used amount is defined" do
        let(:invalid_store_credit) { build(:store_credit, amount: 100, amount_used: 150) }

        it "should not be valid" do
          invalid_store_credit.should_not be_valid
        end

        it "should set the correct error message" do
          invalid_store_credit.valid?
          attribute_name = I18n.t('activerecord.attributes.spree/store_credit.amount_used')
          validation_message = Spree.t('admin.store_credits.errors.amount_used_cannot_be_greater')
          expected_error_message = "#{attribute_name} #{validation_message}"
          invalid_store_credit.errors.full_messages.should include(expected_error_message)
        end
      end

      context "the used amount is not defined yet" do
        let(:store_credit) { build(:store_credit, amount: 100) }

        it "should be valid" do
          store_credit.should be_valid
        end

      end
    end

    describe "amount used less than or equal to amount" do
      subject { build(:store_credit, amount_used: 101.0, amount: 100.0) }

      it "is not valid" do
        subject.should_not be_valid
      end

      it "adds an error message about the invalid amount used" do
        subject.valid?
        subject.errors[:amount_used].should include(Spree.t('admin.store_credits.errors.amount_used_cannot_be_greater'))
      end
    end

    describe "amount authorized less than or equal to amount" do
      subject { build(:store_credit, amount_authorized: 101.0, amount: 100.0) }

      it "is not valid" do
        subject.should_not be_valid
      end

      it "adds an error message about the invalid authorized amount" do
        subject.valid?
        subject.errors[:amount_authorized].should include(Spree.t('admin.store_credits.errors.amount_authorized_exceeds_total_credit'))
      end
    end
  end

  describe "#display_amount" do
    it "returns a Spree::Money instance" do
      store_credit.display_amount.should be_instance_of(Spree::Money)
    end
  end

  describe "#display_amount_used" do
    it "returns a Spree::Money instance" do
      store_credit.display_amount_used.should be_instance_of(Spree::Money)
    end
  end

  describe "#amount_remaining" do
    context "the amount_used is not defined" do
      context "the authorized amount is not defined" do
        it "returns the credited amount" do
          store_credit.amount_remaining.should eq store_credit.amount
        end
      end
      context "the authorized amount is defined" do
        let(:authorized_amount) { 15.00 }

        before { store_credit.update_attributes(amount_authorized: authorized_amount) }

        it "subtracts the authorized amount from the credited amount" do
          store_credit.amount_remaining.should eq (store_credit.amount - authorized_amount)
        end
      end
    end

    context "the amount_used is defined" do
      let(:amount_used) { 10.0 }

      before { store_credit.update_attributes(amount_used: amount_used) }

      context "the authorized amount is not defined" do
        it "subtracts the amount used from the credited amount" do
          store_credit.amount_remaining.should eq (store_credit.amount - amount_used)
        end
      end

      context "the authorized amount is defined" do
        let(:authorized_amount) { 15.00 }

        before { store_credit.update_attributes(amount_authorized: authorized_amount) }

        it "subtracts the amount used and the authorized amount from the credited amount" do
          store_credit.amount_remaining.should eq (store_credit.amount - amount_used - authorized_amount)
        end
      end
    end
  end

  describe "#authorize" do
    context "amount is valid" do
      let(:authorization_amount)       { 1.0 }
      let(:added_authorization_amount) { 3.0 }
      let(:originator) { nil }

      context "amount has not been authorized yet" do

        before { store_credit.update_attributes(amount_authorized: authorization_amount) }

        it "returns true" do
          expect(store_credit.authorize(store_credit.amount - authorization_amount, store_credit.currency)).to be_truthy
        end

        it "adds the new amount to authorized amount" do
          store_credit.authorize(added_authorization_amount, store_credit.currency)
          store_credit.reload.amount_authorized.should eq (authorization_amount + added_authorization_amount)
        end

        context "originator is present" do
          with_model 'OriginatorThing'

          let(:originator) { OriginatorThing.create! } # won't actually be a user. just giving it a valid model here

          subject { store_credit.authorize(added_authorization_amount, store_credit.currency, action_originator: originator) }

          it "records the originator" do
            expect { subject }.to change { Spree::StoreCreditEvent.count }.by(1)
            expect(Spree::StoreCreditEvent.last.originator).to eq originator
          end
        end
      end

      context "authorization has already happened" do
        let!(:auth_event) { create(:store_credit_auth_event, store_credit: store_credit) }

        before { store_credit.update_attributes(amount_authorized: store_credit.amount) }

        it "returns true" do
          expect(store_credit.authorize(store_credit.amount, store_credit.currency, action_authorization_code: auth_event.authorization_code)).to be true
        end
      end
    end

    context "amount is invalid" do
      it "returns false" do
        expect(store_credit.authorize(store_credit.amount * 2, store_credit.currency)).to be false
      end
    end
  end

  describe "#validate_authorization" do
    context "insufficient funds" do
      subject { store_credit.validate_authorization(store_credit.amount * 2, store_credit.currency) }

      it "returns false" do
        expect(subject).to be false
      end

      it "adds an error to the model" do
        subject
        store_credit.errors.full_messages.should include(Spree.t('store_credit_payment_method.insufficient_funds'))
      end
    end

    context "currency mismatch" do
      subject { store_credit.validate_authorization(store_credit.amount, "EUR") }

      it "returns false" do
        expect(subject).to be false
      end

      it "adds an error to the model" do
        subject
        store_credit.errors.full_messages.should include(Spree.t('store_credit_payment_method.currency_mismatch'))
      end
    end

    context "valid authorization" do
      subject { store_credit.validate_authorization(store_credit.amount, store_credit.currency) }

      it "returns true" do
        expect(subject).to be true
      end
    end

    context 'troublesome floats' do
      # 8.21.to_d < 8.21 => true
      let(:store_credit_attrs) { {amount: 8.21} }

      subject { store_credit.validate_authorization(store_credit_attrs[:amount], store_credit.currency) }

      it { should be_truthy }
    end
  end

  describe "#capture" do
    let(:authorized_amount) { 10.00 }
    let(:auth_code)         { "23-SC-20140602164814476128" }

    before do
      store_credit.update_attributes(amount_authorized: authorized_amount, amount_used: 0.0)
      store_credit.stub(authorize: true)
    end

    context "insufficient funds" do
      subject { store_credit.capture(authorized_amount * 2, auth_code,store_credit.currency) }

      it "returns false" do
        expect(subject).to be false
      end

      it "adds an error to the model" do
        subject
        store_credit.errors.full_messages.should include(Spree.t('store_credit_payment_method.insufficient_authorized_amount'))
      end

      it "does not update the store credit model" do
        expect { subject }.to_not change { store_credit }
      end
    end

    context "currency mismatch" do
      subject { store_credit.capture(authorized_amount, auth_code, "EUR") }

      it "returns false" do
        expect(subject).to be false
      end

      it "adds an error to the model" do
        subject
        store_credit.errors.full_messages.should include(Spree.t('store_credit_payment_method.currency_mismatch'))
      end

      it "does not update the store credit model" do
        expect { subject }.to_not change { store_credit }
      end
    end

    context "valid capture" do
      let(:remaining_authorized_amount) { 1 }
      let(:originator) { nil }

      subject { store_credit.capture(authorized_amount - remaining_authorized_amount, auth_code, store_credit.currency, action_originator: originator) }

      it "returns true" do
        expect(subject).to be_truthy
      end

      it "updates the authorized amount to the difference between the captured amount and the authorized amount" do
        subject
        store_credit.reload.amount_authorized.should eq remaining_authorized_amount
      end

      it "updates the used amount to the current used amount plus the captured amount" do
        subject
        store_credit.reload.amount_used.should eq authorized_amount - remaining_authorized_amount
      end

      context "originator is present" do
        with_model 'OriginatorThing'

        let(:originator) { OriginatorThing.create! } # won't actually be a user. just giving it a valid model here

        it "records the originator" do
          expect { subject }.to change { Spree::StoreCreditEvent.count }.by(1)
          expect(Spree::StoreCreditEvent.last.originator).to eq originator
        end
      end
    end
  end

  describe "#void" do
    let(:auth_code)    { "1-SC-20141111111111" }
    let(:store_credit) { create(:store_credit, amount_used: 150.0) }
    let(:originator) { nil }

    subject do
      store_credit.void(auth_code, action_originator: originator)
    end

    context "no event found for auth_code" do

      it "returns false" do
        expect(subject).to be false
      end

      it "adds an error to the model" do
        subject
        store_credit.errors.full_messages.should include(Spree.t('store_credit_payment_method.unable_to_void', auth_code: auth_code))
      end
    end

    context "capture event found for auth_code" do
      let(:captured_amount) { 10.0 }
      let!(:capture_event) { create(:store_credit_auth_event,
                                    action: Spree::StoreCredit::CAPTURE_ACTION,
                                    authorization_code: auth_code,
                                    amount: captured_amount,
                                    store_credit: store_credit) }

      it "returns false" do
        expect(subject).to be false
      end

      it "does not change the amount used on the store credit" do
        expect { subject }.to_not change{ store_credit.amount_used.to_f }
      end
    end

    context "auth event found for auth_code" do
      let(:auth_event) { create(:store_credit_auth_event) }

      let(:authorized_amount) { 10.0 }
      let!(:auth_event) { create(:store_credit_auth_event,
                                 authorization_code: auth_code,
                                 amount: authorized_amount,
                                 store_credit: store_credit) }

      it "returns true" do
        expect(subject).to be true
      end

      it "returns the capture amount to the store credit" do
        expect { subject }.to change{ store_credit.amount_authorized.to_f }.by(-authorized_amount)
      end

      context "originator is present" do
        with_model 'OriginatorThing'

        let(:originator) { OriginatorThing.create! } # won't actually be a user. just giving it a valid model here

        it "records the originator" do
          expect { subject }.to change { Spree::StoreCreditEvent.count }.by(1)
          expect(Spree::StoreCreditEvent.last.originator).to eq originator
        end
      end
    end
  end

  describe "#credit" do
    let(:event_auth_code) { "1-SC-20141111111111" }
    let(:amount_used)     { 10.0 }
    let(:store_credit)    { create(:store_credit, amount_used: amount_used) }
    let!(:capture_event)  { create(:store_credit_auth_event,
                                   action: Spree::StoreCredit::CAPTURE_ACTION,
                                   authorization_code: event_auth_code,
                                   amount: captured_amount,
                                   store_credit: store_credit) }
    let(:originator) { nil }

    subject { store_credit.credit(credit_amount, auth_code, currency, action_originator: originator) }

    context "currency does not match" do
      let(:currency)        { "AUD" }
      let(:credit_amount)   { 5.0 }
      let(:captured_amount) { 100.0 }
      let(:auth_code)       { event_auth_code }

      it "returns false" do
        expect(subject).to be false
      end

      it "adds an error message about the currency mismatch" do
        subject
        store_credit.errors.full_messages.should include(Spree.t('store_credit_payment_method.currency_mismatch'))
      end
    end

    context "unable to find capture event" do
      let(:currency)        { "USD" }
      let(:credit_amount)   { 5.0 }
      let(:captured_amount) { 100.0 }
      let(:auth_code)       { "UNKNOWN_CODE" }

      it "returns false" do
        expect(subject).to be false
      end

      it "adds an error message about the currency mismatch" do
        subject
        store_credit.errors.full_messages.should include(Spree.t('store_credit_payment_method.unable_to_credit', auth_code: auth_code))
      end
    end

    context "amount is more than what is captured" do
      let(:currency)        { "USD" }
      let(:credit_amount)   { 100.0 }
      let(:captured_amount) { 5.0 }
      let(:auth_code)       { event_auth_code }

      it "returns false" do
        expect(subject).to be false
      end

      it "adds an error message about the currency mismatch" do
        subject
        store_credit.errors.full_messages.should include(Spree.t('store_credit_payment_method.unable_to_credit', auth_code: auth_code))
      end
    end

    context "amount is successfully credited" do
      let(:currency)        { "USD" }
      let(:credit_amount)   { 5.0 }
      let(:captured_amount) { 100.0 }
      let(:auth_code)       { event_auth_code }

      context "credit_to_new_allocation is set" do
        before { Spree::StoreCredits::Configuration.stub(:credit_to_new_allocation).and_return(true) }

        it "returns true" do
          expect(subject).to be true
        end

        it "creates a new store credit record" do
          expect { subject }.to change { Spree::StoreCredit.count }.by(1)
        end

        it "does not create a new store credit event on the parent store credit" do
          expect { subject }.to_not change { store_credit.store_credit_events.count }
        end

        context "credits the passed amount to a new store credit record" do
          before do
            subject
            @new_store_credit = Spree::StoreCredit.last
          end

          it "does not set the amount used on hte originating store credit" do
            store_credit.reload.amount_used.should eq amount_used
          end

          it "sets the correct amount on the new store credit" do
            @new_store_credit.amount.should eq credit_amount
          end

          [:user_id, :category_id, :created_by_id, :currency, :type_id].each do |attr|
            it "sets attribute #{attr} inherited from the originating store credit" do
              @new_store_credit.send(attr).should eq store_credit.send(attr)
            end
          end

          it "sets a memo" do
            @new_store_credit.memo.should eq "This is a credit from store credit ID #{store_credit.id}"
          end
        end

        context "originator is present" do
          with_model 'OriginatorThing'

          let(:originator) { OriginatorThing.create! } # won't actually be a user. just giving it a valid model here

          it "records the originator" do
            expect { subject }.to change { Spree::StoreCreditEvent.count }.by(1)
            expect(Spree::StoreCreditEvent.last.originator).to eq originator
          end
        end
      end

      context "credit_to_new_allocation is not set" do
        it "returns true" do
          expect(subject).to be true
        end

        it "credits the passed amount to the store credit amount used" do
          subject
          store_credit.reload.amount_used.should eq (amount_used - credit_amount)
        end

        it "creates a new store credit event" do
          expect { subject }.to change { store_credit.store_credit_events.count }.by(1)
        end
      end
    end
  end

  describe "#amount_used" do
    context "amount used is not defined" do
      subject { Spree::StoreCredit.new }

      it "returns zero" do
        subject.amount_used.should be_zero
      end
    end

    context "amount used is defined" do
      let(:amount_used) { 100.0 }

      subject { create(:store_credit, amount_used: amount_used) }

      it "returns the attribute value" do
        subject.amount_used.should eq amount_used
      end
    end
  end

  describe "#amount_authorized" do
    context "amount authorized is not defined" do
      subject { Spree::StoreCredit.new }

      it "returns zero" do
        subject.amount_authorized.should be_zero
      end
    end

    context "amount authorized is defined" do
      let(:amount_authorized) { 100.0 }

      subject { create(:store_credit, amount_authorized: amount_authorized) }

      it "returns the attribute value" do
        subject.amount_authorized.should eq amount_authorized
      end
    end
  end

  describe "#can_capture?" do
    let(:store_credit) { create(:store_credit) }
    let(:payment)      { create(:payment, state: payment_state) }

    subject { store_credit.can_capture?(payment) }

    context "pending payment" do
      let(:payment_state) { 'pending' }

      it "returns true" do
        expect(subject).to be true
      end
    end

    context "checkout payment" do
      let(:payment_state) { 'checkout' }

      it "returns true" do
        expect(subject).to be true
      end
    end

    context "void payment" do
      let(:payment_state) { Spree::StoreCredit::VOID_ACTION }

      it "returns false" do
        expect(subject).to be false
      end
    end

    context "invalid payment" do
      let(:payment_state) { 'invalid' }

      it "returns false" do
        expect(subject).to be false
      end
    end

    context "complete payment" do
      let(:payment_state) { 'completed' }

      it "returns false" do
        expect(subject).to be false
      end
    end
  end

  describe "#can_void?" do
    let(:store_credit) { create(:store_credit) }
    let(:payment)      { create(:payment, state: payment_state) }

    subject { store_credit.can_void?(payment) }

    context "pending payment" do
      let(:payment_state) { 'pending' }

      it "returns true" do
        expect(subject).to be true
      end
    end

    context "checkout payment" do
      let(:payment_state) { 'checkout' }

      it "returns false" do
        expect(subject).to be false
      end
    end

    context "void payment" do
      let(:payment_state) { Spree::StoreCredit::VOID_ACTION }

      it "returns false" do
        expect(subject).to be false
      end
    end

    context "invalid payment" do
      let(:payment_state) { 'invalid' }

      it "returns false" do
        expect(subject).to be false
      end
    end

    context "complete payment" do
      let(:payment_state) { 'completed' }

      it "returns false" do
        expect(subject).to be false
      end
    end
  end

  describe "#can_credit?" do
    let(:store_credit) { create(:store_credit) }
    let(:payment)      { create(:payment, state: payment_state) }

    subject { store_credit.can_credit?(payment) }

    context "payment is not completed" do
      let(:payment_state) { "pending" }

      it "returns false" do
        expect(subject).to be false
      end
    end

    context "payment is completed" do
      let(:payment_state) { "completed" }

      context "credit is owed on the order" do
        before { payment.order.stub(payment_state: 'credit_owed') }

        context "payment doesn't have allowed credit" do
          before { payment.stub(credit_allowed: 0.0) }

          it "returns false" do
            expect(subject).to be false
          end
        end

        context "payment has allowed credit" do
          before { payment.stub(credit_allowed: 5.0) }

          it "returns true" do
            expect(subject).to be true
          end
        end
      end
    end

    describe "#store_events" do
      context "create" do
        context "user has one store credit" do
          let(:store_credit_amount) { 100.0 }

          subject { create(:store_credit, amount: store_credit_amount) }

          it "creates a store credit event" do
            expect { subject }.to change { Spree::StoreCreditEvent.count }.by(1)
          end

          it "makes the store credit event an allocation event" do
            subject.store_credit_events.first.action.should eq Spree::StoreCredit::ALLOCATION_ACTION
          end

          it "saves the user's total store credit in the event" do
            subject.store_credit_events.first.user_total_amount.should eq store_credit_amount
          end
        end

        context "user has multiple store credits" do
          let(:store_credit_amount)            { 100.0 }
          let(:additional_store_credit_amount) { 200.0 }

          let(:user)                           { create(:user) }
          let!(:store_credit)                  { create(:store_credit, user: user, amount: store_credit_amount) }

          subject { create(:store_credit, user: user, amount: additional_store_credit_amount) }

          it "saves the user's total store credit in the event" do
            subject.store_credit_events.first.user_total_amount.should eq (store_credit_amount + additional_store_credit_amount)
          end
        end

        context "an action is specified" do
          it "creates an event with the set action" do
            store_credit = build(:store_credit)
            store_credit.action = Spree::StoreCredit::VOID_ACTION
            store_credit.action_authorization_code = "1-SC-TEST"

            expect { store_credit.save! }.to change { Spree::StoreCreditEvent.where(action: Spree::StoreCredit::VOID_ACTION).count }.by(1)
          end
        end
      end
    end
  end
end
