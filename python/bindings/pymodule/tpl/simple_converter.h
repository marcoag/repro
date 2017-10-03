#pragma once

// BEGIN: drake/common/hash.h
#include <cassert>
#include <cstddef>
#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <set>
#include <typeindex>
#include <utility>
#include <vector>

namespace drake {

/** Combines a given hash value @p seed and a hash of parameter @p v. */
template <class T>
size_t hash_combine(size_t seed, const T& v);

template <class T, class... Rest>
size_t hash_combine(size_t seed, const T& v, Rest... rest) {
  return hash_combine(hash_combine(seed, v), rest...);
}

/** Computes the hash value of @p v using std::hash. */
template <class T>
struct hash_value {
  size_t operator()(const T& v) { return std::hash<T>{}(v); }
};

/** Computes the hash value of a tuple @p s. */
template <typename ... Ts>
struct hash_value<std::tuple<Ts...>> {
  size_t operator()(const std::tuple<Ts...>& s) {
    return impl(s, std::make_index_sequence<sizeof...(Ts)>());
  }

 private:
  template <size_t ... Is>
  size_t impl(const std::tuple<Ts...>& s, std::index_sequence<Is...> seq = {}) {
    size_t seed{};
    return hash_combine(seed, std::get<Is>(s)...);
  }
};

/** Combines two hash values into one. The following code is public domain
 *  according to http://www.burtleburtle.net/bob/hash/doobs.html. */
template <class T>
inline size_t hash_combine(size_t seed, const T& v) {
  seed ^= hash_value<T>{}(v) + 0x9e3779b9 + (seed << 6) + (seed >> 2);
  return seed;
}

}  // namespace drake
// END

namespace simple_converter {

// - BEGIN: Added
template <typename ... Ts>
struct type_pack {
  // Make tuple of equal size.
  typedef std::tuple<std::conditional<true, Ts, std::type_index>...>
      type_index_tuple;

  static type_index_tuple make_type_index_tuple() {
    return std::make_tuple(std::type_index(typeid(Ts))...);
  }

  static size_t hash() {
    return drake::hash_value<type_index_tuple>(make_type_index_tuple());
  }

  template <template <typename...> class Tpl>
  using type = Tpl<Ts...>;
};

template <typename T>
struct type_pack_inner_impl {
  static_assert(!std::is_same<T, T>::value, "Wrong template");
};

template <template <typename ... Ts> class Tpl, typename ... Ts>
struct type_pack_inner_impl<Tpl<Ts...>> {
  using type = type_pack<Ts...>;

  template <template <typename...> class TplIn>
  using type_constrained =
      typename std::conditional<
          std::is_same<TplIn<Ts...>, Tpl<Ts...>>::value, 
            type,
            std::false_type
      >::type;
};

template <typename T>
using type_pack_inner = typename type_pack_inner_impl<T>::type;

template <typename T, template <typename...> class Tpl>
using type_pack_inner_constrained =
    typename type_pack_inner_impl<T>::template type_constraind<Tpl>;

// - END: Added

// Simple (less robust) version of Drake's SystemScalarConverter
template <template <typename...> class Tpl>
class SimpleConverter {
 public:
  typedef std::function<void*(const void*)> ErasedConverter;
  typedef std::pair<size_t, size_t> Key;  
  typedef std::map<Key, ErasedConverter> Conversions;

  template <typename Pack>
  using type = typename Pack::template type<Tpl>;

  template <typename Type>
  using pack = type_pack_inner_constrained<Type, Tpl>;

  template <typename From, typename To>
  using Converter = std::function<std::unique_ptr<To> (const From&)>;

  template <typename From, typename To>
  inline static Key get_key() {
    return Key(pack<From>::hash(), pack<To>::hash());
  }

  template <typename From, typename To>
  void Add(const Converter<From, To>& converter) {
    ErasedConverter erased = [converter](const void* from_raw) {
      const From* from = static_cast<const From*>(from_raw);
      return converter(from).release();
    };
    Key key = get_key<From, To>();
    assert(conversions_.find(key) == conversions_.end());
    conversions_[key] = erased;
  }

  template <typename From, typename To>
  std::unique_ptr<To> Convert(const From& from) {
    Key key = get_key<From, To>();
    auto iter = conversions_.find(key);
    assert(iter != conversions_.end());
    ErasedConverter erased = iter->second;
    std::unique_ptr<To> out(
        static_cast<To*>(erased(&from)));
    return out;
  }

 private:
  Conversions conversions_;
};

}  // namespace simple_converter
