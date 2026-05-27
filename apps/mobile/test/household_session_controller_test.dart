import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';

class FakeHouseholdGateway implements HouseholdGateway {
  final households = <Household>[];
  final authStateController = StreamController<void>.broadcast();
  var sentEmail = '';
  Object? sendOtpError;
  Object? loadHouseholdsError;
  Completer<void>? sendOtpCompleter;

  @override
  Stream<void> get authStateChanges => authStateController.stream;

  @override
  Future<void> sendOtp(String email) async {
    if (sendOtpError != null) throw sendOtpError!;
    sentEmail = email;
    await sendOtpCompleter?.future;
  }

  @override
  Future<List<Household>> loadHouseholds() async {
    if (loadHouseholdsError != null) throw loadHouseholdsError!;
    return households;
  }

  @override
  Future<Household> createHousehold(String name) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<void> uploadInitialData(String householdId) async {}

  void emitAuthStateChange() {
    authStateController.add(null);
  }

  Future<void> close() {
    return authStateController.close();
  }
}

void main() {
  test('sendOtp trims email before sending', () async {
    final gateway = FakeHouseholdGateway();
    final controller = HouseholdSessionController(gateway);

    await controller.sendOtp(' owner@example.com ');

    expect(gateway.sentEmail, 'owner@example.com');
    expect(controller.state.email, 'owner@example.com');
    expect(controller.state.isSubmitting, isFalse);
  });

  test('sendOtp exposes gateway errors in state', () async {
    final gateway = FakeHouseholdGateway()..sendOtpError = StateError('boom');
    final controller = HouseholdSessionController(gateway);

    await controller.sendOtp('owner@example.com');

    expect(controller.state.error, contains('boom'));
    expect(controller.state.isSubmitting, isFalse);
  });

  test('refreshHouseholds stores loaded households', () async {
    final gateway = FakeHouseholdGateway()
      ..households.add(
        const Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      );
    final controller = HouseholdSessionController(gateway);

    await controller.refreshHouseholds();

    expect(controller.state.households.single.id, 'household_1');
  });

  test('refreshHouseholds exposes gateway errors in state', () async {
    final gateway = FakeHouseholdGateway()
      ..loadHouseholdsError = StateError('offline');
    final controller = HouseholdSessionController(gateway);

    await controller.refreshHouseholds();

    expect(controller.state.error, contains('offline'));
    expect(controller.state.households, isEmpty);
  });

  test('auth state changes refresh households', () async {
    final gateway = FakeHouseholdGateway();
    final controller = HouseholdSessionController(gateway);

    gateway.households.add(
      const Household(
        id: 'household_1',
        name: 'Home',
        ownerId: 'owner_1',
        defaultStorageArea: 'fridge',
      ),
    );
    gateway.emitAuthStateChange();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.households.single.id, 'household_1');

    controller.dispose();
    await gateway.close();
  });

  test('refreshHouseholds preserves active OTP submission', () async {
    final gateway = FakeHouseholdGateway()
      ..sendOtpCompleter = Completer<void>()
      ..households.add(
        const Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      );
    final controller = HouseholdSessionController(gateway);

    final sendOtpFuture = controller.sendOtp('owner@example.com');
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.isSubmitting, isTrue);

    await controller.refreshHouseholds();

    expect(controller.state.isSubmitting, isTrue);
    expect(controller.state.households.single.id, 'household_1');

    gateway.sendOtpCompleter!.complete();
    await sendOtpFuture;

    expect(controller.state.isSubmitting, isFalse);

    controller.dispose();
    await gateway.close();
  });
}
