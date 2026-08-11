import 'package:flutter/material.dart';

import '../services/api_response.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../utils/validators.dart';
import '../widgets/error_banner.dart';
import '../shell/app_shell.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final gymNameController = TextEditingController();
  final ownerNameController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final emailController = TextEditingController();
  final cityController = TextEditingController();
  final stateController = TextEditingController();
  final addressController = TextEditingController();

  final _ownerNameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _cityFocus = FocusNode();
  final _stateFocus = FocusNode();
  final _addressFocus = FocusNode();

  bool isLoading = false;
  String? _error;

  Future<void> register() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      final result = await AuthService().register(
        gymName: gymNameController.text.trim(),
        ownerName: ownerNameController.text.trim(),
        phone: phoneController.text.trim(),
        password: passwordController.text.trim(),
        city: cityController.text.trim(),
        state: stateController.text.trim(),
        address: addressController.text.trim(),
        email: emailController.text.trim(),
      );

      if (!mounted) return;
      final data = result['data'];

      await StorageService.saveAuthData(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
        userId: data['user']['id'],
        gymId: data['user']['gym_id'],
        userName: data['user']['name'],
        role: data['user']['role'],
      );

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AppShell()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Something went wrong. Please try again.';
      });
    }

    if (!mounted) return;
    setState(() => isLoading = false);
  }

  @override
  void dispose() {
    gymNameController.dispose();
    ownerNameController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    emailController.dispose();
    cityController.dispose();
    stateController.dispose();
    addressController.dispose();

    _ownerNameFocus.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _emailFocus.dispose();
    _cityFocus.dispose();
    _stateFocus.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  Widget field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    FocusNode? focusNode,
    FocusNode? nextFocus,
    TextInputAction textInputAction = TextInputAction.next,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        focusNode: focusNode,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        onFieldSubmitted: (_) {
          if (nextFocus != null) {
            nextFocus.requestFocus();
          } else {
            register();
          }
        },
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Gym'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              field(
                gymNameController,
                'Gym Name',
                nextFocus: _ownerNameFocus,
                validator: (v) => Validators.required(v, 'Gym name'),
              ),
              field(
                ownerNameController,
                'Owner Name',
                focusNode: _ownerNameFocus,
                nextFocus: _phoneFocus,
                validator: (v) => Validators.required(v, 'Owner name'),
              ),
              field(
                phoneController,
                'Phone',
                focusNode: _phoneFocus,
                nextFocus: _passwordFocus,
                keyboardType: TextInputType.phone,
                validator: Validators.phone,
              ),
              field(
                passwordController,
                'Password',
                obscure: true,
                focusNode: _passwordFocus,
                nextFocus: _emailFocus,
                validator: (v) => Validators.required(v, 'Password'),
              ),
              field(
                emailController,
                'Email',
                focusNode: _emailFocus,
                nextFocus: _cityFocus,
                keyboardType: TextInputType.emailAddress,
                validator: Validators.emailOptional,
              ),
              field(cityController, 'City', focusNode: _cityFocus, nextFocus: _stateFocus),
              field(stateController, 'State', focusNode: _stateFocus, nextFocus: _addressFocus),
              field(
                addressController,
                'Address',
                focusNode: _addressFocus,
                textInputAction: TextInputAction.done,
              ),

              if (_error != null) ...[
                const SizedBox(height: 4),
                ErrorBanner.inline(message: _error!),
              ],

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading ? null : register,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  child: isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text('Register'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
