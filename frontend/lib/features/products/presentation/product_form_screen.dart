import 'package:flutter/material.dart' hide required;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/validation/validators.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/forms/app_select_field.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../theme/app_typography.dart';
import '../../categories/data/category_providers.dart';
import '../data/product_models.dart';
import '../data/product_providers.dart';

/// Create/edit (spec §8) — a full page, not a dialog, because Products has
/// by far the most fields of any module (§8's exhaustive Basic/Inventory/
/// Financial/Optional grouping). The Optional section is visually
/// de-emphasized (collapsed by default) rather than removed — "do not force
/// unnecessary fields" (§8) without silently dropping fields the spec
/// explicitly lists.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.productId});

  /// Null for create, set for edit.
  final String? productId;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _code = TextEditingController();
  final _sku = TextEditingController();
  final _barcode = TextEditingController();
  final _brand = TextEditingController();
  final _description = TextEditingController();
  final _shortDescription = TextEditingController();
  final _currentQuantity = TextEditingController(text: '0');
  final _minStock = TextEditingController();
  final _maxStock = TextEditingController();
  final _reorderLevel = TextEditingController();
  final _warehouse = TextEditingController(text: 'Main Warehouse');
  final _shelfRackBin = TextEditingController();
  final _purchaseCost = TextEditingController();
  final _sellingPrice = TextEditingController();
  final _wholesalePrice = TextEditingController();
  final _discountPrice = TextEditingController();
  final _taxRate = TextEditingController();
  final _size = TextEditingController();
  final _length = TextEditingController();
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _color = TextEditingController();
  final _material = TextEditingController();
  final _model = TextEditingController();
  final _manufacturer = TextEditingController();
  final _serialNumber = TextEditingController();
  final _batchNumber = TextEditingController();
  final _warrantyPeriod = TextEditingController();

  String? _categoryId;
  String _unit = commonUnits.first;
  ProductType _productType = ProductType.finishedGood;
  ProductStatus _status = ProductStatus.active;
  bool _optionalExpanded = false;
  bool _loadingExisting = true;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.productId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _loadExisting();
    } else {
      _loadingExisting = false;
    }
  }

  Future<void> _loadExisting() async {
    final product = await ref.read(productRepositoryProvider).getById(widget.productId!);
    _name.text = product.name;
    _code.text = product.code;
    _sku.text = product.sku ?? '';
    _barcode.text = product.barcode ?? '';
    _brand.text = product.brand ?? '';
    _description.text = product.description ?? '';
    _shortDescription.text = product.shortDescription ?? '';
    _currentQuantity.text = '${product.currentQuantity}';
    _minStock.text = product.minStock?.toString() ?? '';
    _maxStock.text = product.maxStock?.toString() ?? '';
    _reorderLevel.text = product.reorderLevel?.toString() ?? '';
    _warehouse.text = product.warehouseName ?? '';
    _shelfRackBin.text = product.shelfRackBin ?? '';
    _purchaseCost.text = product.purchaseCost?.toString() ?? '';
    _sellingPrice.text = product.sellingPrice?.toString() ?? '';
    _wholesalePrice.text = product.wholesalePrice?.toString() ?? '';
    _discountPrice.text = product.discountPrice?.toString() ?? '';
    _taxRate.text = product.taxRate?.toString() ?? '';
    _size.text = product.size ?? '';
    _length.text = product.length?.toString() ?? '';
    _width.text = product.width?.toString() ?? '';
    _height.text = product.height?.toString() ?? '';
    _weight.text = product.weight?.toString() ?? '';
    _color.text = product.color ?? '';
    _material.text = product.material ?? '';
    _model.text = product.model ?? '';
    _manufacturer.text = product.manufacturer ?? '';
    _serialNumber.text = product.serialNumber ?? '';
    _batchNumber.text = product.batchNumber ?? '';
    _warrantyPeriod.text = product.warrantyPeriod ?? '';
    setState(() {
      _categoryId = product.categoryId;
      _unit = product.unit;
      _productType = product.productType;
      _status = product.status;
      _loadingExisting = false;
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name, _code, _sku, _barcode, _brand, _description, _shortDescription, _currentQuantity, _minStock,
      _maxStock, _reorderLevel, _warehouse, _shelfRackBin, _purchaseCost, _sellingPrice, _wholesalePrice,
      _discountPrice, _taxRate, _size, _length, _width, _height, _weight, _color, _material, _model,
      _manufacturer, _serialNumber, _batchNumber, _warrantyPeriod,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _d(TextEditingController c) => c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());
  int? _i(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
  String? _s(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final draft = ProductDraft(
      name: _name.text.trim(),
      code: _code.text.trim(),
      sku: _s(_sku),
      barcode: _s(_barcode),
      // No category is a product the server accepts — `createProductSchema` has
      // `categoryId: idSchema.nullable().optional()`, and `''` is already how
      // this model carries "none" (see `_fromJson`, which maps a null id to it).
      //
      // The asterisk came off this field because a brand-new business has no
      // categories to choose from, but the guard that enforced it was left in
      // place: `if (_categoryId == null) _error = requiredFieldMessage`, which
      // blocked the save anyway and named no field while doing it. An unmarked
      // field that silently refuses to submit is worse than a marked one.
      categoryId: _categoryId ?? '',
      brand: _s(_brand),
      description: _s(_description),
      shortDescription: _s(_shortDescription),
      status: _status,
      productType: _productType,
      currentQuantity: _i(_currentQuantity) ?? 0,
      minStock: _i(_minStock),
      maxStock: _i(_maxStock),
      reorderLevel: _i(_reorderLevel),
      warehouseName: _s(_warehouse),
      shelfRackBin: _s(_shelfRackBin),
      unit: _unit,
      purchaseCost: _d(_purchaseCost),
      sellingPrice: _d(_sellingPrice),
      wholesalePrice: _d(_wholesalePrice),
      discountPrice: _d(_discountPrice),
      taxRate: _d(_taxRate),
      size: _s(_size),
      length: _d(_length),
      width: _d(_width),
      height: _d(_height),
      weight: _d(_weight),
      color: _s(_color),
      material: _s(_material),
      model: _s(_model),
      manufacturer: _s(_manufacturer),
      serialNumber: _s(_serialNumber),
      batchNumber: _s(_batchNumber),
      warrantyPeriod: _s(_warrantyPeriod),
    );

    try {
      final repo = ref.read(productRepositoryProvider);
      if (_isEditing) {
        await repo.update(widget.productId!, draft);
      } else {
        await repo.create(draft);
      }
      await ref.read(productListControllerProvider.notifier).reload();
      ref.invalidate(productPickerOptionsProvider);
      if (_isEditing) ref.invalidate(productByIdProvider(widget.productId!));
      if (mounted) context.go(AppRoutes.products);
    } catch (_) {
      if (mounted) setState(() => _error = AppLocalizations.of(context)!.unableToSave);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final categoriesAsync = ref.watch(categoryPickerOptionsProvider);

    if (_loadingExisting) {
      return PageScaffold(
        title: l10n.edit,
        showBackButton: true,
        backFallbackRoute: AppRoutes.products,
        body: const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      );
    }

    return PageScaffold(
      title: _isEditing ? '${l10n.edit} — ${_name.text}' : '${l10n.add} ${l10n.navProducts}',
      showBackButton: true,
      backFallbackRoute: AppRoutes.products,
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            // Basic (§8)
            AppCard(
              title: Text(l10n.details),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 14,
                children: [
                  AppTextField(label: l10n.fieldName, controller: _name, required: true, validator: required(l10n.requiredFieldMessage)),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      SizedBox(width: 220, child: AppTextField(label: l10n.fieldCode, controller: _code, required: true, validator: required(l10n.requiredFieldMessage))),
                      SizedBox(width: 220, child: AppTextField(label: l10n.fieldSku, controller: _sku)),
                      SizedBox(width: 220, child: AppTextField(label: l10n.fieldBarcode, controller: _barcode)),
                      SizedBox(width: 220, child: AppTextField(label: l10n.fieldBrand, controller: _brand)),
                    ],
                  ),
                  categoriesAsync.when(
                    // NOT required, despite the asterisk this used to carry.
                    //
                    // createProductSchema has categoryId as nullable and
                    // optional — a product with no category is one the server
                    // accepts. The asterisk was decoration while the dropdown
                    // left required unchecked; enforcing it now would block
                    // something the system allows.
                    //
                    // And it would block it at the worst moment: a brand new
                    // business has no categories at all, so this list is empty
                    // on the first visit. A mandatory field with nothing in it
                    // to choose is not a field somebody forgot to fill in — it
                    // is a dead end, and nothing on the form says "create a
                    // category first". That is the same shape as the missing
                    // warehouse that made stock impossible to add.
                    data: (categories) => AppDropdownField<String>(
                      label: l10n.fieldCategory,
                      value: _categoryId,
                      options: [for (final c in categories) AppSelectOption(c.id, c.name)],
                      onChanged: (value) => setState(() => _categoryId = value),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      SizedBox(
                        width: 260,
                        child: AppDropdownField<ProductType>(
                          label: l10n.fieldModule,
                          value: _productType,
                          options: [
                            AppSelectOption(ProductType.finishedGood, l10n.navProducts),
                            AppSelectOption(ProductType.rawMaterial, l10n.navProduction),
                            AppSelectOption(ProductType.component, l10n.fieldModel),
                          ],
                          onChanged: (value) => setState(() => _productType = value ?? ProductType.finishedGood),
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: AppDropdownField<ProductStatus>(
                          label: l10n.fieldStatus,
                          value: _status,
                          options: [
                            AppSelectOption(ProductStatus.active, l10n.statusActive),
                            AppSelectOption(ProductStatus.inactive, l10n.statusInactive),
                            AppSelectOption(ProductStatus.discontinued, l10n.statusCancelled),
                          ],
                          onChanged: (value) => setState(() => _status = value ?? ProductStatus.active),
                        ),
                      ),
                    ],
                  ),
                  AppTextField(label: l10n.fieldShortDescription, controller: _shortDescription),
                  AppTextField.multiline(label: l10n.fieldDescription, controller: _description, maxLines: 3),
                ],
              ),
            ),

            // Inventory (§8/§10)
            AppCard(
              title: Text(l10n.navInventory),
              child: Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(width: 160, child: AppTextField.number(label: l10n.fieldCurrentQuantity, controller: _currentQuantity, allowDecimal: false)),
                  SizedBox(width: 160, child: AppTextField.number(label: l10n.fieldMinStock, controller: _minStock, allowDecimal: false)),
                  SizedBox(width: 160, child: AppTextField.number(label: l10n.fieldMaxStock, controller: _maxStock, allowDecimal: false)),
                  SizedBox(width: 160, child: AppTextField.number(label: l10n.fieldReorderLevel, controller: _reorderLevel, allowDecimal: false)),
                  SizedBox(
                    width: 180,
                    child: AppDropdownField<String>(
                      label: l10n.fieldUnit,
                      value: _unit,
                      options: [for (final u in commonUnits) AppSelectOption(u, u)],
                      onChanged: (value) => setState(() => _unit = value ?? commonUnits.first),
                    ),
                  ),
                  SizedBox(width: 220, child: AppTextField(label: l10n.fieldWarehouse, controller: _warehouse)),
                  SizedBox(width: 220, child: AppTextField(label: l10n.fieldShelfRackBin, controller: _shelfRackBin)),
                ],
              ),
            ),

            // Financial (§8)
            AppCard(
              title: Text(l10n.fieldPurchaseCost),
              child: Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(width: 170, child: AppTextField.number(label: l10n.fieldPurchaseCost, controller: _purchaseCost)),
                  SizedBox(width: 170, child: AppTextField.number(label: l10n.fieldSellingPrice, controller: _sellingPrice)),
                  SizedBox(width: 170, child: AppTextField.number(label: l10n.fieldWholesalePrice, controller: _wholesalePrice)),
                  SizedBox(width: 170, child: AppTextField.number(label: l10n.fieldDiscountPrice, controller: _discountPrice)),
                  SizedBox(width: 170, child: AppTextField.number(label: l10n.fieldTax, controller: _taxRate)),
                ],
              ),
            ),

            // Optional (§8) — collapsed by default: "do not force unnecessary fields."
            AppCard(
              title: InkWell(
                onTap: () => setState(() => _optionalExpanded = !_optionalExpanded),
                child: Row(
                  children: [
                    Expanded(child: Text(l10n.optionalField, style: AppTypography.cardTitle)),
                    Icon(_optionalExpanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),
              child: _optionalExpanded
                  ? Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        SizedBox(width: 170, child: AppTextField(label: l10n.fieldSize, controller: _size)),
                        SizedBox(width: 130, child: AppTextField.number(label: 'L (cm)', controller: _length)),
                        SizedBox(width: 130, child: AppTextField.number(label: 'W (cm)', controller: _width)),
                        SizedBox(width: 130, child: AppTextField.number(label: 'H (cm)', controller: _height)),
                        SizedBox(width: 150, child: AppTextField.number(label: l10n.fieldWeight, controller: _weight)),
                        SizedBox(width: 170, child: AppTextField(label: l10n.fieldColor, controller: _color)),
                        SizedBox(width: 170, child: AppTextField(label: l10n.fieldMaterial, controller: _material)),
                        SizedBox(width: 170, child: AppTextField(label: l10n.fieldModel, controller: _model)),
                        SizedBox(width: 200, child: AppTextField(label: l10n.fieldManufacturer, controller: _manufacturer)),
                        SizedBox(width: 200, child: AppTextField(label: l10n.fieldSerialNumber, controller: _serialNumber)),
                        SizedBox(width: 200, child: AppTextField(label: l10n.fieldBatchNumber, controller: _batchNumber)),
                        SizedBox(width: 200, child: AppTextField(label: l10n.fieldWarrantyPeriod, controller: _warrantyPeriod)),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),

            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 12,
              children: [
                AppButton(label: l10n.cancel, variant: AppButtonVariant.text, onPressed: _saving ? null : () => context.go(AppRoutes.products)),
                AppButton(label: _isEditing ? l10n.update : l10n.create, loading: _saving, onPressed: _saving ? null : _submit),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
