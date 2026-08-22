import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';

/// Mutable scratch state carried across the multi-screen auth + onboarding flow.
class SignupFlow {
  const SignupFlow({
    this.email = '',
    this.isSignup = true,
    this.signupToken,
    this.selectToken,
    this.accounts = const [],
    this.fullName = '',
    this.password = '',
    this.useFor,
    this.manageCategory,
    this.workCategory,
    this.devCode,
  });

  final String email;
  final bool isSignup;
  final String? signupToken;
  final String? selectToken;
  final List<AccountSummary> accounts;
  final String fullName;
  final String password;
  final String? useFor;
  final String? manageCategory;
  final String? workCategory;

  /// Dev-mode OTP echo so the flow is testable without an inbox.
  final String? devCode;

  SignupFlow copyWith({
    String? email,
    bool? isSignup,
    String? signupToken,
    String? selectToken,
    List<AccountSummary>? accounts,
    String? fullName,
    String? password,
    String? useFor,
    String? manageCategory,
    String? workCategory,
    String? devCode,
  }) =>
      SignupFlow(
        email: email ?? this.email,
        isSignup: isSignup ?? this.isSignup,
        signupToken: signupToken ?? this.signupToken,
        selectToken: selectToken ?? this.selectToken,
        accounts: accounts ?? this.accounts,
        fullName: fullName ?? this.fullName,
        password: password ?? this.password,
        useFor: useFor ?? this.useFor,
        manageCategory: manageCategory ?? this.manageCategory,
        workCategory: workCategory ?? this.workCategory,
        devCode: devCode ?? this.devCode,
      );
}

final signupFlowProvider = NotifierProvider<SignupFlowNotifier, SignupFlow>(SignupFlowNotifier.new);

class SignupFlowNotifier extends Notifier<SignupFlow> {
  @override
  SignupFlow build() => const SignupFlow();

  void start({required String email, required bool isSignup}) =>
      state = SignupFlow(email: email, isSignup: isSignup);

  void update(SignupFlow Function(SignupFlow) transform) => state = transform(state);

  void reset() => state = const SignupFlow();
}
