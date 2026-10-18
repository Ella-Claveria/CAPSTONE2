// Recommended Products in Search: the buyer's own history first; with no
// history, what buyers in their town buy; failing that, the newest posts.
import 'package:agritrade/services/personal_recommendations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> product(
  String name,
  String category, {
  int postedDay = 1,
  int orders = 0,
  num quantity = 10,
}) => {
  'name': name,
  'commodity': name,
  'category': category,
  'quantity': quantity,
  'completedOrderCount': orders,
  'createdAt': Timestamp.fromDate(DateTime(2026, 10, postedDay)),
};

void main() {
  final products = {
    'rice': product('Rice', 'Grains', postedDay: 1, orders: 30),
    'corn': product('Corn', 'Grains', postedDay: 2),
    'tomato': product('Tomato', 'Vegetables', postedDay: 3),
    'eggplant': product('Eggplant', 'Vegetables', postedDay: 4),
    'mango': product('Mango', 'Fruits', postedDay: 5),
    'gone': product('Cabbage', 'Vegetables', postedDay: 9, quantity: 0),
  };

  test('no history and no sales in town: the newest posts, in stock', () {
    final result = PersonalRecommendations.recommend(products: products);
    expect(result.basis, RecommendationBasis.newest);
    expect(result.ids.first, 'mango');
    expect(result.ids, isNot(contains('gone')));
  });

  test('no history: what buyers in their town buy', () {
    final result = PersonalRecommendations.recommend(
      products: products,
      areaSales: [
        {'productName': 'Corn', 'category': 'Grains'},
        {'productName': 'Corn', 'category': 'Grains'},
        {'productName': 'Tomato', 'category': 'Vegetables'},
      ],
    );
    expect(result.basis, RecommendationBasis.area);
    expect(result.ids.first, 'corn');
    // Same category as the town's favourite comes next.
    expect(result.ids[1], 'tomato');
  });

  test('their own purchases come first', () {
    final result = PersonalRecommendations.recommend(
      products: products,
      orders: [
        {
          'category': 'Vegetables',
          'commodity': 'Tomato',
          'status': 'completed',
        },
      ],
      areaSales: [
        {'productName': 'Corn', 'category': 'Grains'},
      ],
    );
    expect(result.basis, RecommendationBasis.personal);
    expect(result.ids.first, 'tomato');
    expect(result.ids[1], 'eggplant');
  });

  test('liked categories and searches count too', () {
    expect(
      PersonalRecommendations.recommend(
        products: products,
        likedIds: ['mango'],
      ).ids.first,
      'mango',
    );
    expect(
      PersonalRecommendations.recommend(
        products: products,
        searches: ['corn'],
      ).ids.first,
      'corn',
    );
  });

  test('rejected or cancelled orders are not counted', () {
    final result = PersonalRecommendations.recommend(
      products: products,
      orders: [
        {'category': 'Fruits', 'commodity': 'Mango', 'status': 'rejected'},
      ],
    );
    expect(result.basis, RecommendationBasis.newest);
  });
}
