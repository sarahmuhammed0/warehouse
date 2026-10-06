// A required field that is submitted empty must say so, and the border must go
// red so the person can see WHICH field it was.
//
// Before this, `required: true` only drew the red asterisk above the input. The
// actual check was a separate `validator: required(...)` the caller also had to
// remember, and three call sites did not:
//
//   Employee form → Role        a dropdown; `required` was ignored outright
//   Product form  → Category    the same
//   Return form   → Reason      a text field with no validator
//
// `AppDropdownField` ignored `required` for every caller, and
// `AppSearchableSelectField`, `AppMultiSelectField` and the two date fields had
// no way to show an error at all — they used a bare `InputDecorator`, which is
// chrome and not part of the form, so `Form.validate()` could not reach them.
//
// Each test here submits an empty required field and asserts the error surfaces.
// The last group proves the border that error produces is the error colour, and
// that a field which is NOT required still accepts empty — the fix must not
// quietly make every field mandatory.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_os_app/core/validation/validators.dart';
import 'package:warehouse_os_app/l10n/generated/app_localizations.dart';
import 'package:warehouse_os_app/shared/forms/app_date_field.dart';
import 'package:warehouse_os_app/shared/forms/app_select_field.dart';
import 'package:warehouse_os_app/shared/forms/app_text_field.dart';
import 'package:warehouse_os_app/theme/app_colors.dart';
import 'package:warehouse_os_app/theme/app_theme.dart';

/// The form key is handed back so a test can submit the way a screen does —
/// `_formKey.currentState!.validate()` — rather than poking at the field.
Widget _form(GlobalKey<FormState> key, Widget field) => MaterialApp(
  theme: AppTheme.light(),
  localizationsDelegates: const [
    ...AppLocalizations.localizationsDelegates,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Form(
      key: key,
      child: SingleChildScrollView(child: field),
    ),
  ),
);

/// Whatever `InputDecorator` the field built, with the error text the form put
/// on it. This is the widget that paints the border, so its `errorText` is what
/// decides whether the border is drawn from `errorBorder` or `enabledBorder`.
InputDecoration _decoration(WidgetTester tester) {
  final decorators = tester.widgetList<InputDecorator>(find.byType(InputDecorator));
  expect(decorators, isNotEmpty, reason: 'the field did not build an InputDecorator, so it can never show an error');
  return decorators.first.decoration;
}

void main() {
  group('a required field submitted empty reports itself', () {
    testWidgets('AppTextField — the Return form\'s Reason, which had no validator', (tester) async {
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(_form(key, const AppTextField(label: 'Reason', required: true)));

      expect(key.currentState!.validate(), isFalse, reason: 'an empty required field must not pass validation');
      await tester.pump();

      expect(find.text('This field is required.'), findsOneWidget);
      expect(_decoration(tester).errorText, 'This field is required.');
    });

    testWidgets('AppDropdownField — the Employee form\'s Role and the Product form\'s Category', (tester) async {
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(
        _form(
          key,
          AppDropdownField<String>(
            label: 'Role',
            required: true,
            value: null,
            options: const [AppSelectOption('1', 'Owner'), AppSelectOption('2', 'Manager')],
            onChanged: (_) {},
          ),
        ),
      );

      expect(key.currentState!.validate(), isFalse, reason: 'no option chosen in a required dropdown');
      await tester.pump();

      expect(find.text('This field is required.'), findsOneWidget);
      expect(_decoration(tester).errorText, 'This field is required.');
    });

    testWidgets('AppSearchableSelectField — nothing typed', (tester) async {
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(
        _form(
          key,
          AppSearchableSelectField<String>(
            label: 'Customer',
            required: true,
            options: const [AppSelectOption('1', 'Ahmed')],
            onSelected: (_) {},
          ),
        ),
      );

      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('This field is required.'), findsOneWidget);
    });

    testWidgets('AppSearchableSelectField — typed, but never picked from the list', (tester) async {
      // The silent one: text in the box but `onSelected` never fired, so the
      // form holds no value. Submitting used to be accepted and the choice
      // dropped.
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(
        _form(
          key,
          AppSearchableSelectField<String>(
            label: 'Customer',
            required: true,
            options: const [AppSelectOption('1', 'Ahmed')],
            onSelected: (_) {},
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField), 'Ahm');
      await tester.pump();

      expect(key.currentState!.validate(), isFalse, reason: 'a partial match is not a selection');
      await tester.pump();
      expect(find.text('This field is required.'), findsOneWidget);
    });

    testWidgets('AppSearchableSelectField — a full option label does pass', (tester) async {
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(
        _form(
          key,
          AppSearchableSelectField<String>(
            label: 'Customer',
            required: true,
            initialValue: const AppSelectOption('1', 'Ahmed'),
            options: const [AppSelectOption('1', 'Ahmed')],
            onSelected: (_) {},
          ),
        ),
      );

      // An edit form opens with the existing choice already in the box; it must
      // not be reported as missing.
      expect(key.currentState!.validate(), isTrue);
    });

    testWidgets('AppMultiSelectField — nothing ticked', (tester) async {
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(
        _form(
          key,
          AppMultiSelectField<String>(
            label: 'Permissions',
            required: true,
            selected: const <String>{},
            options: const [AppSelectOption('1', 'Read'), AppSelectOption('2', 'Write')],
            onChanged: (_) {},
          ),
        ),
      );

      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(_decoration(tester).errorText, 'This field is required.');
    });

    testWidgets('AppDateField — no date picked', (tester) async {
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(
        _form(key, AppDateField(label: 'Delivery date', required: true, value: null, onChanged: (_) {})),
      );

      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(_decoration(tester).errorText, 'This field is required.');
    });

    testWidgets('AppDateRangeField — no range picked', (tester) async {
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(
        _form(key, AppDateRangeField(label: 'Period', required: true, value: null, onChanged: (_) {})),
      );

      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(_decoration(tester).errorText, 'This field is required.');
    });
  });

  group('the border the error produces is red', () {
    testWidgets('the theme draws an errored field with the error colour, and a normal one without', (tester) async {
      // Two halves of the same claim. The field reports `errorText` (asserted
      // above, per widget), and the theme turns `errorText` into a border in
      // `colors.error` — that pairing is what the user sees as "the border went
      // red". Asserting the theme here rather than sampling pixels keeps the
      // check readable and still fails if either half is changed.
      late ThemeData theme;
      late AppColors colors;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              theme = Theme.of(context);
              colors = context.colors;
              return const SizedBox();
            },
          ),
        ),
      );

      final input = theme.inputDecorationTheme;
      final errorSide = (input.errorBorder as OutlineInputBorder).borderSide;
      final focusedErrorSide = (input.focusedErrorBorder as OutlineInputBorder).borderSide;
      final normalSide = (input.enabledBorder as OutlineInputBorder).borderSide;

      expect(errorSide.color, colors.error, reason: 'an errored field must be outlined in the error colour');
      expect(focusedErrorSide.color, colors.error, reason: 'and still while it has focus');
      expect(normalSide.color, isNot(colors.error), reason: 'a field with no error must not look like one that has');
    });

    // The test above proves the theme is right; these prove it actually reaches
    // each field. Every one of the six widgets is submitted empty, and the
    // assertion is made on the decoration THAT FIELD ended up with — Material
    // merges the theme into it before `InputDecorator` paints, and paints
    // `errorBorder` precisely when `errorText` is non-null. So a field whose
    // `errorText` is set and whose `errorBorder` is `colors.error` is a field
    // drawn with a red border, per field rather than in general.
    //
    // Both halves are asserted together on purpose: a field that reported an
    // error but inherited no red border, or a red border on a field reporting no
    // error, would each pass one half of the old check and still be wrong.
    for (final (name, field) in <(String, Widget)>[
      ('AppTextField', const AppTextField(label: 'Reason', required: true)),
      (
        'AppDropdownField',
        AppDropdownField<String>(
          label: 'Role',
          required: true,
          value: null,
          options: const [AppSelectOption('1', 'Manager')],
          onChanged: (_) {},
        ),
      ),
      (
        'AppSearchableSelectField',
        AppSearchableSelectField<String>(
          label: 'Customer',
          required: true,
          options: const [AppSelectOption('1', 'Ahmed')],
          onSelected: (_) {},
        ),
      ),
      (
        'AppMultiSelectField',
        AppMultiSelectField<String>(
          label: 'Warehouses',
          required: true,
          selected: const <String>{},
          options: const [AppSelectOption('1', 'Main')],
          onChanged: (_) {},
        ),
      ),
      ('AppDateField', AppDateField(label: 'Date', required: true, value: null, onChanged: (_) {})),
      ('AppDateRangeField', AppDateRangeField(label: 'Period', required: true, value: null, onChanged: (_) {})),
    ]) {
      testWidgets('$name — submitted empty, the field itself is drawn with the red border', (tester) async {
        final key = GlobalKey<FormState>();
        late AppColors colors;
        await tester.pumpWidget(
          _form(
            key,
            Builder(
              builder: (context) {
                colors = context.colors;
                return field;
              },
            ),
          ),
        );

        expect(key.currentState!.validate(), isFalse, reason: '$name accepted an empty required value');
        await tester.pump();

        final decoration = _decoration(tester);
        expect(decoration.errorText, isNotNull, reason: '$name has no errorText, so no red border can be painted');
        final border = decoration.errorBorder;
        expect(border, isNotNull, reason: '$name inherited no errorBorder from the theme');
        expect(
          border!.borderSide.color,
          colors.error,
          reason: '$name is in its error state but the border it paints is not red',
        );
      });
    }
  });

  group('the fix does not make everything mandatory', () {
    testWidgets('a field that is not required still accepts empty', (tester) async {
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(_form(key, const AppTextField(label: 'Notes')));

      expect(key.currentState!.validate(), isTrue);
      await tester.pump();
      expect(find.text('This field is required.'), findsNothing);
      expect(_decoration(tester).errorText, isNull);
    });

    testWidgets('a dropdown that is not required accepts nothing selected', (tester) async {
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(
        _form(
          key,
          AppDropdownField<String>(
            label: 'Category',
            value: null,
            options: const [AppSelectOption('1', 'Seats')],
            onChanged: (_) {},
          ),
        ),
      );

      expect(key.currentState!.validate(), isTrue);
    });

    testWidgets("a caller's own validator still runs, and keeps its own wording", (tester) async {
      // Both rules on one field. The caller's rule is asked first so a field
      // that already says something specific keeps saying it; the generic
      // required check answers only when that rule has no objection.
      //
      // `positiveNumber()` is the real validator from
      // lib/core/validation/validators.dart, which deliberately passes an empty
      // value through — so an empty box is reported as missing rather than as
      // holding a negative number it does not hold.
      final key = GlobalKey<FormState>();
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _form(
          key,
          AppTextField.number(
            label: 'Selling price',
            controller: controller,
            required: true,
            validator: positiveNumber('Must be a positive number.'),
          ),
        ),
      );

      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('This field is required.'), findsOneWidget);
      expect(find.text('Must be a positive number.'), findsNothing);

      // Now a value that is present but wrong: the caller's rule takes over.
      await tester.enterText(find.byType(TextFormField), '-5');
      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Must be a positive number.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '120');
      expect(key.currentState!.validate(), isTrue);
    });
  });

  group('correcting the field clears the red without submitting again', () {
    testWidgets('typing into an errored required field removes the error', (tester) async {
      final key = GlobalKey<FormState>();
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_form(key, AppTextField(label: 'Reason', controller: controller, required: true)));

      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(_decoration(tester).errorText, isNotNull);

      // No second validate() call — `autovalidateMode: onUserInteraction` is
      // what makes the border go back to normal as the person fixes it.
      await tester.enterText(find.byType(TextFormField), 'Damaged on arrival');
      await tester.pump();

      expect(_decoration(tester).errorText, isNull);
    });
  });
}
