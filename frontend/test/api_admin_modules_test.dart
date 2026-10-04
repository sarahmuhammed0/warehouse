// The modules wired in the "no demo data" pass: staff and roles, the activity
// trail, notifications, Settings, variants, custom fields, backups and the
// System Admin's per-business drill-downs.
//
// Same job as `api_repositories_test.dart`: pin the mapping in both directions
// against a stubbed HTTP layer, because a repository that spells a field
// `name` where the server says `label` compiles, analyses clean, and simply
// shows a blank.

import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_os_app/core/error/failure.dart';
import 'package:warehouse_os_app/core/repositories/paged_query.dart';
import 'package:warehouse_os_app/features/activity_history/data/api_audit_repository.dart';
import 'package:warehouse_os_app/features/admin/data/admin_business_models.dart';
import 'package:warehouse_os_app/features/admin/data/api_admin_repository.dart';
import 'package:warehouse_os_app/features/employees/data/api_employee_repository.dart';
import 'package:warehouse_os_app/features/employees/data/employee_models.dart';
import 'package:warehouse_os_app/features/notifications/data/api_notification_repository.dart';
import 'package:warehouse_os_app/features/notifications/data/notification_models.dart';
import 'package:warehouse_os_app/features/orders/data/api_order_repository.dart';
import 'package:warehouse_os_app/features/orders/data/order_models.dart';
import 'package:warehouse_os_app/features/products/data/api_product_variant_repository.dart';
import 'package:warehouse_os_app/features/settings/data/backup_repository.dart';
import 'package:warehouse_os_app/features/settings/data/custom_fields_repository.dart';
import 'package:warehouse_os_app/features/settings/data/settings_repository.dart';

import 'fakes/stub_api.dart';

void main() {
  group('Staff ↔ /api/users', () {
    test('the schema says disabled, this module says inactive — both directions', () async {
      final s = stubbedApi({
        'GET /users': listEnvelope([
          {
            'id': 8553,
            'businessId': 8551,
            'name': 'Lana Aziz',
            'phone': '+9647500000012',
            'email': null,
            'roleId': 12,
            'roleName': 'Sales Staff',
            'status': 'disabled',
            'lastLoginAt': '2026-09-29 09:00:00',
            'createdAt': '2026-09-28 20:39:00',
          },
        ]),
      });

      final page = await ApiEmployeeRepository(s.client).list(const PagedQuery());
      final row = page.items.single;

      expect(row.status, EmployeeStatus.inactive);
      expect(row.roleName, 'Sales Staff');
      expect(row.roleId, '12');
      expect(row.lastLoginAt, isNotNull);
    });

    test('setStatus sends the schema\'s word, not this module\'s', () async {
      final s = stubbedApi({'PATCH /users/8553': oneEnvelope({'id': 8553, 'status': 'disabled'})});

      await ApiEmployeeRepository(s.client).setStatus('8553', EmployeeStatus.inactive);

      expect(s.stub.calls.single.body!['status'], 'disabled');
    });

    test('the generated first password is surfaced once, and only once', () async {
      final s = stubbedApi({
        'POST /users': oneEnvelope({
          'id': 9001,
          'businessId': 8551,
          'name': 'Nia Rashid',
          'phone': '+9647500000099',
          'roleId': 12,
          'roleName': 'Sales Staff',
          'status': 'active',
          'createdAt': '2026-09-29 12:00:00',
          'temporaryPassword': 'Xy8vQ2mNb1Tz',
        }),
      });

      final repo = ApiEmployeeRepository(s.client);
      await repo.create(const EmployeeDraft(name: 'Nia Rashid', phone: '+9647500000099', roleId: '12'));

      expect(repo.lastTemporaryPassword, 'Xy8vQ2mNb1Tz');
      expect(
        s.stub.calls.single.body!.containsKey('password'),
        isFalse,
        reason: 'no password is invented client-side; the server generates it',
      );
    });

    test('a changed phone is refused here, because the server would ignore it silently', () async {
      // The update schema has no `phone`, and zod strips a key it does not
      // know — so passing it through would answer 200 with the number
      // unchanged, and the owner would leave believing they had changed it.
      final s = stubbedApi({
        'GET /users/8553': oneEnvelope({
          'id': 8553,
          'businessId': 8551,
          'name': 'Lana Aziz',
          'phone': '+9647500000012',
          'roleId': 12,
          'roleName': 'Sales Staff',
          'status': 'active',
          'createdAt': '2026-09-28 20:39:00',
        }),
        'PATCH /users/8553': oneEnvelope({'id': 8553}),
      });

      await expectLater(
        ApiEmployeeRepository(s.client).update(
          '8553',
          const EmployeeDraft(name: 'Lana Aziz', phone: '+9647999999999', roleId: '12'),
        ),
        throwsA(isA<Failure>()),
      );
      expect(
        s.stub.calls.where((c) => c.method == 'PATCH'),
        isEmpty,
        reason: 'nothing is sent when the edit cannot be honoured',
      );
    });

    test('an unchanged phone updates normally, and is never sent', () async {
      final s = stubbedApi({
        'GET /users/8553': oneEnvelope({
          'id': 8553,
          'businessId': 8551,
          'name': 'Lana Aziz',
          'phone': '+9647500000012',
          'roleId': 12,
          'roleName': 'Sales Staff',
          'status': 'active',
          'createdAt': '2026-09-28 20:39:00',
        }),
        'PATCH /users/8553': oneEnvelope({
          'id': 8553,
          'businessId': 8551,
          'name': 'Lana A. Aziz',
          'phone': '+9647500000012',
          'roleId': 13,
          'roleName': 'Accountant',
          'status': 'active',
          'createdAt': '2026-09-28 20:39:00',
        }),
      });

      final updated = await ApiEmployeeRepository(s.client).update(
        '8553',
        const EmployeeDraft(name: 'Lana A. Aziz', phone: '+9647500000012', roleId: '13'),
      );

      final patch = s.stub.calls.firstWhere((c) => c.method == 'PATCH');
      expect(patch.body!.containsKey('phone'), isFalse);
      expect(patch.body!['roleId'], 13, reason: 'an id, not the string the picker held');
      expect(updated.roleName, 'Accountant');
    });
  });

  group('Roles ↔ /api/roles', () {
    test('a permission set is replaced whole, by PUT', () async {
      final s = stubbedApi({
        'PUT /roles/12/permissions': oneEnvelope({
          'id': 12,
          'name': 'Sales Staff',
          'isSystemRole': true,
          'permissions': ['orders.view', 'orders.create'],
        }),
      });

      final role = await ApiEmployeeRepository(s.client)
          .updateRolePermissions('12', {'orders.view', 'orders.create'});

      final call = s.stub.calls.single;
      expect(call.method, 'PUT', reason: 'an omitted key means "untick", which PATCH cannot express');
      expect((call.body!['permissions'] as List).toSet(), {'orders.view', 'orders.create'});
      expect(role.permissions, {'orders.view', 'orders.create'});
      expect(role.isSystemRole, isTrue);
    });

    test('emptying a role is a real edit, not a no-op', () async {
      final s = stubbedApi({
        'PUT /roles/12/permissions': oneEnvelope({
          'id': 12,
          'name': 'Sales Staff',
          'isSystemRole': false,
          'permissions': <String>[],
        }),
      });

      final role = await ApiEmployeeRepository(s.client).updateRolePermissions('12', {});

      expect(s.stub.calls.single.body!['permissions'], isEmpty);
      expect(role.permissions, isEmpty);
    });
  });

  group('Activity trail ↔ /api/audit-logs', () {
    test('an event with no actor reads as System, never as a blank name', () async {
      final s = stubbedApi({
        'GET /audit-logs': listEnvelope([
          {
            'id': 17381,
            'actorName': null,
            'module': 'businesses',
            'action': 'business.registered',
            'description': 'Self-registration received.',
            'ipAddress': '10.0.0.4',
            'referenceId': 42,
            'createdAt': '2026-09-29 16:41:16',
          },
        ]),
      });

      final row = (await ApiAuditRepository(s.client).list(const PagedQuery())).items.single;

      expect(row.userName, 'System');
      expect(row.action, 'business.registered');
      expect(row.referenceId, '42');
      expect(row.ipAddress, '10.0.0.4');
    });

    test('the module filter reaches the server rather than being applied locally', () async {
      final s = stubbedApi({'GET /audit-logs': listEnvelope([])});

      await ApiAuditRepository(s.client).list(
        const PagedQuery(filters: {'module': 'inventory'}),
      );

      expect(s.stub.calls.single.path, contains('module=inventory'));
    });
  });

  group('Notifications ↔ /api/notifications', () {
    test('each type maps, and a row links to the record it is about', () async {
      final s = stubbedApi({
        'GET /notifications': listEnvelope([
          {
            'id': 5,
            'type': 'low_stock',
            'title': 'Low stock',
            'body': 'Oak Plank: 3 left.',
            'referenceType': 'products',
            'referenceId': 8954,
            'isRead': false,
            'readAt': null,
            'createdAt': '2026-09-29 10:00:00',
          },
          {
            'id': 6,
            'type': 'production_completed',
            'title': 'Production complete',
            'body': 'Run finished.',
            'referenceType': 'production_orders',
            'referenceId': 3,
            'readAt': '2026-09-29 11:00:00',
            'createdAt': '2026-09-29 10:30:00',
          },
        ]),
      });

      final rows = await ApiNotificationRepository(s.client).list();

      expect(rows.first.type, NotificationType.lowStock);
      expect(rows.first.targetRoute, '/products/8954');
      expect(rows.first.isUnread, isTrue);
      expect(rows.last.type, NotificationType.productionCompleted);
      expect(rows.last.targetRoute, '/production/3');
      expect(rows.last.isUnread, isFalse);
    });

    test('an unrecognised subject gets no route rather than a guessed one', () async {
      final s = stubbedApi({
        'GET /notifications': listEnvelope([
          {
            'id': 7,
            'type': 'system_alert',
            'title': 'Notice',
            'body': 'Something happened.',
            'referenceType': 'something_new',
            'referenceId': 1,
            'createdAt': '2026-09-29 10:00:00',
          },
        ]),
      });

      expect((await ApiNotificationRepository(s.client).list()).single.targetRoute, isNull);
    });

    test('the badge reads the server\'s count, not the length of a page', () async {
      final s = stubbedApi({'GET /notifications/unread-count': oneEnvelope({'unread': 7})});

      expect(await ApiNotificationRepository(s.client).unreadCount(), 7);
    });
  });

  group('Settings ↔ /business, /settings, /documents', () {
    Map<String, Map<String, dynamic>> settingsStubs() => {
      'GET /business': oneEnvelope({'id': 8551, 'name': 'Karwan Furniture Factory', 'currency': 'IQD'}),
      'GET /settings': oneEnvelope({
        'values': {
          'inventory.allow_negative_stock': true,
          'inventory.low_stock_threshold_default': 6,
          'payments.cash_enabled': true,
          'payments.bank_transfer_enabled': false,
          'payments.card_enabled': true,
          'security.min_password_length': 10,
        },
      }),
      'GET /documents/numbering': listEnvelope([
        {'documentType': 'sale', 'prefix': 'INV', 'nextNumber': 42},
        {'documentType': 'order', 'prefix': 'ORD', 'nextNumber': 8},
        {'documentType': 'production', 'prefix': 'PRDN', 'nextNumber': 3},
      ]),
      'GET /documents/pdf-template': oneEnvelope({
        'footerText': 'Thank you.',
        'fields': {'logo': false, 'taxInfo': true, 'signature': false},
      }),
    };

    test('one screen is assembled from four different places', () async {
      final loaded = await ApiSettingsRepository(stubbedApi(settingsStubs()).client).load();

      expect(loaded.businessName, 'Karwan Furniture Factory');
      expect(loaded.currency, 'IQD');
      expect(loaded.negativeInventoryAllowed, isTrue);
      expect(loaded.lowStockDefaultThreshold, 6);
      expect(loaded.bankTransferEnabled, isFalse);
      expect(loaded.minPasswordLength, 10);
      expect(loaded.invoicePrefix, 'INV');
      expect(loaded.orderPrefix, 'ORD');
      expect(loaded.productionNumberPrefix, 'PRDN');
      expect(loaded.startingNumber, 42);
      expect(loaded.pdfShowLogo, isFalse);
      expect(loaded.pdfShowSignature, isFalse);
      expect(loaded.pdfFooterText, 'Thank you.');
    });

    test('only what changed is sent, and to the endpoint that owns it', () async {
      final s = stubbedApi({
        ...settingsStubs(),
        'PATCH /settings': oneEnvelope({'values': <String, dynamic>{}}),
        'PATCH /documents/numbering/sale': oneEnvelope({'documentType': 'sale'}),
      });
      final repo = ApiSettingsRepository(s.client);
      final previous = await repo.load();
      s.stub.calls.clear();

      await repo.save(
        previous: previous,
        next: previous.copyWith(cashPaymentsEnabled: false, invoicePrefix: 'INVOICE'),
      );

      final paths = s.stub.calls.map((c) => '${c.method} ${c.path}').toList();
      expect(paths, contains('PATCH /settings'));
      expect(paths, contains('PATCH /documents/numbering/sale'));
      expect(
        paths.any((p) => p.contains('/business')),
        isFalse,
        reason: 'the business record did not change, so it is not written',
      );
      expect(
        paths.any((p) => p.contains('numbering/order')),
        isFalse,
        reason: 'a sequence with no change must not be touched — its counter only moves forward',
      );

      final values = s.stub.calls.firstWhere((c) => c.path == '/settings').body!['values'] as Map;
      expect(values.keys.single, 'payments.cash_enabled');
      expect(values['payments.cash_enabled'], isFalse);
    });

    test('the starting number applies to invoices only, never to every sequence', () async {
      final s = stubbedApi({
        ...settingsStubs(),
        'PATCH /documents/numbering/sale': oneEnvelope({'documentType': 'sale'}),
      });
      final repo = ApiSettingsRepository(s.client);
      final previous = await repo.load();
      s.stub.calls.clear();

      await repo.save(previous: previous, next: previous.copyWith(startingNumber: 100));

      final sale = s.stub.calls.single;
      expect(sale.path, '/documents/numbering/sale');
      expect(sale.body!['nextNumber'], 100);
    });

    test('a PDF save sends only the flags this screen owns, so the rest survive', () async {
      final s = stubbedApi({
        ...settingsStubs(),
        'PUT /documents/pdf-template': oneEnvelope({'footerText': 'Bye.'}),
      });
      final repo = ApiSettingsRepository(s.client);
      final previous = await repo.load();
      s.stub.calls.clear();

      await repo.save(previous: previous, next: previous.copyWith(pdfShowLogo: true));

      final fields = s.stub.calls.single.body!['fields'] as Map;
      expect(fields.keys.toSet(), {'logo', 'taxInfo', 'signature'});
      expect(
        fields.containsKey('paymentTerms'),
        isFalse,
        reason: 'the server merges key by key, so an unmentioned block keeps its value',
      );
    });

    test('nothing is written when nothing changed', () async {
      final s = stubbedApi(settingsStubs());
      final repo = ApiSettingsRepository(s.client);
      final previous = await repo.load();
      s.stub.calls.clear();

      await repo.save(previous: previous, next: previous);

      expect(s.stub.calls, isEmpty);
    });
  });

  group('Variants ↔ /api/products/:id/variants', () {
    test('a free-text label survives the round trip through §9\'s attributes', () async {
      final s = stubbedApi({
        'GET /products/5/variants': listEnvelope([
          {
            'id': 31,
            'sku': 'CHR-BLK',
            'sellingPrice': 75.0,
            'purchaseCost': 40.0,
            'attributes': {'label': 'Colour: Black'},
            'quantity': 12,
          },
        ]),
      });

      final variant = (await ApiProductVariantRepository(s.client).list('5')).single;

      expect(variant.attributeLabel, 'Colour: Black');
      expect(variant.price, 75.0);
      expect(variant.quantity, 12);
    });

    test('a variant created elsewhere still reads, rather than showing blank', () async {
      final s = stubbedApi({
        'GET /products/5/variants': listEnvelope([
          {'id': 32, 'sku': 'CHR-OAK', 'attributes': {'colour': 'Oak', 'size': 'Large'}},
        ]),
      });

      final variant = (await ApiProductVariantRepository(s.client).list('5')).single;

      expect(variant.attributeLabel, 'colour: Oak, size: Large');
    });

    test('an opening quantity becomes a real stock movement, not an invisible balance', () async {
      final s = stubbedApi({
        'POST /products/5/variants': oneEnvelope({'id': 33, 'sku': 'CHR-WHT'}),
        'POST /inventory/adjust': oneEnvelope({'id': 1}),
        'GET /products/5/variants': listEnvelope([
          {'id': 33, 'sku': 'CHR-WHT', 'attributes': {'label': 'Colour: White'}, 'quantity': 4},
        ]),
      });

      await ApiProductVariantRepository(s.client).create(
        '5',
        attributeLabel: 'Colour: White',
        sku: 'CHR-WHT',
        price: 75,
        cost: 40,
        quantity: 4,
        warehouseId: 2,
      );

      final adjust = s.stub.calls.firstWhere((c) => c.path == '/inventory/adjust');
      expect(adjust.body!['variantId'], 33, reason: 'a variant is its own stock slot');
      expect(adjust.body!['quantity'], 4);
      expect(adjust.body!['movementType'], 'manual_increase');
    });

    test('no opening quantity means no movement at all', () async {
      final s = stubbedApi({
        'POST /products/5/variants': oneEnvelope({'id': 34, 'sku': 'CHR-RED'}),
        'GET /products/5/variants': listEnvelope([
          {'id': 34, 'sku': 'CHR-RED', 'attributes': {'label': 'Colour: Red'}, 'quantity': 0},
        ]),
      });

      await ApiProductVariantRepository(s.client).create(
        '5',
        attributeLabel: 'Colour: Red',
        sku: 'CHR-RED',
        price: 75,
        cost: 40,
        quantity: 0,
        warehouseId: 2,
      );

      expect(s.stub.calls.any((c) => c.path == '/inventory/adjust'), isFalse);
    });
  });

  group('Custom fields ↔ /api/custom-fields', () {
    test('a label becomes a stable machine key', () {
      expect(keyFor('Wood type'), 'wood_type');
      expect(keyFor('  Fabric / Colour  '), 'fabric_colour');
      expect(keyFor('2026 batch'), startsWith('field_'), reason: 'a key must start with a letter');
    });

    test('the key is sent alongside the label, so a rename cannot orphan values', () async {
      final s = stubbedApi({'POST /custom-fields': oneEnvelope({'id': 3})});

      await ApiCustomFieldsRepository(s.client).create('Wood type');

      final body = s.stub.calls.single.body!;
      expect(body['label'], 'Wood type');
      expect(body['fieldKey'], 'wood_type');
      expect(body['entityType'], 'product');
      expect(body['fieldType'], 'text');
    });
  });

  group('Backups ↔ /api/admin/backups', () {
    test('the server\'s own answer is carried through, not translated into success', () async {
      final s = stubbedApi({
        'POST /admin/backups': oneEnvelope({
          'id': 1,
          'status': 'pending',
          'fileProduced': false,
          'note': 'Recorded as requested. No file has been written.',
        }),
      });

      final outcome = await ApiBackupRepository(s.client).start();

      expect(outcome.fileProduced, isFalse);
      expect(outcome.message, contains('No file has been written'));
    });

    test('history shows why a request produced nothing', () async {
      final s = stubbedApi({
        'GET /admin/backups': listEnvelope([
          {
            'id': 1,
            'status': 'pending',
            'sizeBytes': null,
            'errorMessage': 'No configured backup target.',
            'createdAt': '2026-09-29 12:00:00',
          },
        ]),
      });

      final row = (await ApiBackupRepository(s.client).list()).single;

      expect(row.status, 'pending');
      expect(row.fileSizeBytes, isNull);
      expect(row.note, 'No configured backup target.');
    });

    test('demo mode offers no history at all, rather than a plausible one', () async {
      expect(await LocalBackupRepository().list(), isEmpty);
      expect((await LocalBackupRepository().start()).fileProduced, isFalse);
    });
  });

  group('System Admin ↔ /api/admin/businesses', () {
    test('a business maps, and no password-reset date is invented', () async {
      final s = stubbedApi({
        'GET /admin/businesses': listEnvelope([
          {
            'id': 8551,
            'name': 'Karwan Furniture Factory',
            'businessType': 'furniture_factory',
            'phone': '+9647500000003',
            'status': 'active',
            'createdAt': '2026-09-28 20:39:24',
          },
        ]),
      });

      final row = (await ApiAdminRepository(s.client).listBusinesses(const PagedQuery())).items.single;

      expect(row.name, 'Karwan Furniture Factory');
      expect(row.status, BusinessAccountStatus.active);
      expect(
        row.lastPasswordResetAt,
        isNull,
        reason: 'the server does not record it, so the detail screen must not show one',
      );
    });

    test('a status filter is sent as the wire value, not a Dart enum', () async {
      // The Businesses screen stores a BusinessAccountStatus in its filters.
      // Interpolated, that is "BusinessAccountStatus.active", which the endpoint
      // rejects — the whole list came back 422 and the screen showed "Something
      // went wrong". It only broke against a real server: the demo repository
      // compares the enum in memory and never serialises it.
      final s = stubbedApi({'GET /admin/businesses': listEnvelope([])});

      await ApiAdminRepository(s.client).listBusinesses(
        const PagedQuery(filters: {'status': BusinessAccountStatus.active}),
      );

      final sent = s.stub.calls.single.fullPath;
      expect(sent, contains('status=active'));
      expect(
        sent,
        isNot(contains('BusinessAccountStatus')),
        reason: 'the Dart enum name must never reach the wire',
      );
    });

    test('a reset surfaces the generated password once', () async {
      final s = stubbedApi({
        'POST /admin/businesses/8551/reset-password': oneEnvelope({'temporaryPassword': 'Zq4TnP9xLm2W'}),
        'GET /admin/businesses/8551': oneEnvelope({
          'id': 8551,
          'name': 'Karwan Furniture Factory',
          'businessType': 'furniture_factory',
          'phone': '+9647500000003',
          'status': 'active',
          'createdAt': '2026-09-28 20:39:24',
        }),
      });

      final repo = ApiAdminRepository(s.client);
      await repo.resetBusinessPassword('8551');

      expect(repo.lastGeneratedPassword, 'Zq4TnP9xLm2W');
    });

    test('a per-business order drill-down carries its lines, so the total is not 0.00', () async {
      final s = stubbedApi({
        'GET /admin/businesses/8551/orders': oneEnvelope({
          'items': [
            {
              'id': 2779,
              'businessId': 8551,
              'orderNumber': 'ORD-2026-000001',
              'orderType': 'standard',
              'status': 'confirmed',
              'grandTotal': 1302,
              'paidAmount': 500,
              'extraCharges': 0,
              'customerName': 'Ahmed Al-Rashid',
              'orderDate': '2026-09-28 20:39:28',
              'items': [
                {'productId': 1, 'productName': 'Oak Dining Table', 'quantity': 2, 'unitPrice': 320.0, 'taxAmount': 32.0},
                {'productId': 2, 'productName': 'Oak Dining Chair', 'quantity': 8, 'unitPrice': 75.0, 'taxAmount': 30.0},
              ],
            },
          ],
          'limit': 200,
          'truncated': false,
        }),
      });

      final order = (await ApiOrderRepository(s.client)
              .listForBusiness('8551', type: OrderType.standard))
          .single;

      expect(order.items, hasLength(2));
      expect(
        order.grandTotal,
        1302,
        reason: "the model computes the total from its lines — it must match the server's",
      );
      expect(s.stub.calls.single.path, contains('type=standard'));
    });

    test('platform activity names the business, and says Platform when there is none', () async {
      final s = stubbedApi({
        'GET /admin/activity': listEnvelope([
          {'description': 'Login succeeded.', 'businessName': 'Platform', 'createdAt': '2026-09-29 16:44:31'},
          {'description': 'Settings changed.', 'businessName': 'Karwan Furniture Factory', 'createdAt': '2026-09-29 16:40:00'},
        ]),
      });

      final rows = await ApiAdminRepository(s.client).recentActivity();

      expect(rows.first.businessName, 'Platform');
      expect(rows.last.businessName, 'Karwan Furniture Factory');
    });
  });
}
