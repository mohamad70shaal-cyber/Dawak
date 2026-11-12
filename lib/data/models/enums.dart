enum UserRole {
  customer,
  pharmacist,
  admin;

  static UserRole parse(String? v) => UserRole.values.firstWhere((UserRole r) => r.name == v, orElse: () => UserRole.customer);
}

enum ApprovalStatus {
  pending,
  approved,
  rejected,
  suspended;

  static ApprovalStatus parse(String? v) =>
      ApprovalStatus.values.firstWhere((ApprovalStatus r) => r.name == v, orElse: () => ApprovalStatus.pending);
}

enum MemberRole {
  owner,
  manager,
  cashier;

  static MemberRole parse(String? v) => MemberRole.values.firstWhere((MemberRole r) => r.name == v, orElse: () => MemberRole.cashier);

  /// Owners and managers manage the product list, prices and see money; cashiers only sell, handle orders and answer requests.
  bool get canManage => this == MemberRole.owner || this == MemberRole.manager;
}

enum OrderStatus {
  pending,
  accepted,
  readyForPickup,
  completed,
  rejected,
  cancelled,
  expired;

  static OrderStatus parse(String? v) {
    switch (v) {
      case 'accepted':
        return OrderStatus.accepted;
      case 'ready_for_pickup':
        return OrderStatus.readyForPickup;
      case 'completed':
        return OrderStatus.completed;
      case 'rejected':
        return OrderStatus.rejected;
      case 'cancelled':
        return OrderStatus.cancelled;
      case 'expired':
        return OrderStatus.expired;
      default:
        return OrderStatus.pending;
    }
  }

  String get wire {
    switch (this) {
      case OrderStatus.readyForPickup:
        return 'ready_for_pickup';
      default:
        return name;
    }
  }

  /// Translation key of the label.
  String get labelKey => 'order_status_$wire';

  bool get isTerminal =>
      this == OrderStatus.completed || this == OrderStatus.rejected || this == OrderStatus.cancelled;

  /// States in which the pharmacy has promised to keep the order ready for the customer (a promise, not stock).
  bool get isPromised => this == OrderStatus.accepted || this == OrderStatus.readyForPickup;
}

/// How recently a pharmacy confirmed a listed price/availability (`private.listing_freshness`: `recent` = 7 days).
enum Freshness {
  recent,
  old;

  static Freshness parse(String? v) => v == 'recent' ? Freshness.recent : Freshness.old;

  /// Translation key of the label ("confirmed recently" / "not confirmed for a while").
  String get labelKey => this == Freshness.recent ? 'fresh_recent' : 'fresh_old';
}

/// State of an availability request ("ask the pharmacies nearby").
enum RequestStatus {
  open,
  closed,
  expired;

  static RequestStatus parse(String? v) {
    switch (v) {
      case 'closed':
        return RequestStatus.closed;
      case 'expired':
        return RequestStatus.expired;
      default:
        return RequestStatus.open;
    }
  }

  String get labelKey => 'req_status_$name';

  bool get isOpen => this == RequestStatus.open;
}

/// A pharmacy's answer to an availability request.
enum RequestAnswer {
  available,
  unavailable;

  static RequestAnswer? parse(String? v) {
    switch (v) {
      case 'available':
        return RequestAnswer.available;
      case 'unavailable':
        return RequestAnswer.unavailable;
      default:
        return null;
    }
  }
}
