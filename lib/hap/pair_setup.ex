defmodule HAP.PairSetup do
  @moduledoc """
  Implements the Pair Setup flow described in section 4.7 of Apple's [HomeKit Accessory Protocol Specification](https://developer.apple.com/homekit/). 
  """

  use Bitwise

  require Logger

  @kTLVType_Method 0x00
  @kTLVType_Identifier 0x01
  @kTLVType_Salt 0x02
  @kTLVType_PublicKey 0x03
  @kTLVType_Proof 0x04
  @kTLVType_EncryptedData 0x05
  @kTLVType_State 0x06
  @kTLVType_Error 0x07

  @kTLVError_Authentication <<0x02>>
  @kTLVError_Unavailable <<0x06>>
  @kTLVError_Busy <<0x07>>

  @doc """
  Handles `<M1>` messages and returns `<M2>` messages
  """
  def handle_message(%{@kTLVType_State => <<1>>, @kTLVType_Method => <<0>>}, %HAP.PairingStates.Unpaired{
        username: i,
        pairing_code: p
      }) do
    {n, g} = Strap.prime_group(3072)
    protocol = Strap.protocol(:srp6a, n, g, :sha512)
    s = :crypto.strong_rand_bytes(16)
    v = Strap.verifier(protocol, i, p, s)
    server = Strap.server(protocol, v)
    b = Strap.public_value(server)

    response = %{@kTLVType_State => <<2>>, @kTLVType_PublicKey => b, @kTLVType_Salt => s}
    state = %HAP.PairingStates.PairingM2{server: server, username: i, salt: s}
    {:ok, response, state}
  end

  def handle_message(%{@kTLVType_State => <<1>>, @kTLVType_Method => <<0>>}, %HAP.PairingStates.Paired{} = state) do
    response = %{@kTLVType_State => <<2>>, @kTLVType_Error => @kTLVError_Unavailable}
    {:ok, response, state}
  end

  def handle_message(%{@kTLVType_State => <<1>>, @kTLVType_Method => <<0>>}, state) do
    response = %{@kTLVType_State => <<2>>, @kTLVType_Error => @kTLVError_Busy}
    {:ok, response, state}
  end

  @doc """
  Handles `<M3>` messages and returns `<M4>` messages
  """
  def handle_message(
        %{@kTLVType_State => <<3>>, @kTLVType_PublicKey => a, @kTLVType_Proof => proof},
        %HAP.PairingStates.PairingM2{
          server: server,
          username: i,
          salt: s
        } = state
      ) do
    # Strap doesn't implement M1 / M2 management, so we need to do it ourselves
    #
    # M_1 = H(H(N) xor H(g), H(I), s, A, B, K)
    # M_2 = H(A, M_1, K)

    {n, g} = Strap.prime_group(3072)
    h_n = n |> hash |> to_int
    h_g = g |> to_bin |> hash |> to_int
    xor = bxor(h_n, h_g) |> to_bin
    h_i = i |> hash
    b = server |> Strap.public_value()
    {:ok, shared_key} = Strap.session_key(server, a)
    k = shared_key |> hash
    m_1 = hash(xor <> h_i <> s <> a <> b <> k)

    case proof do
      ^m_1 ->
        response = %{@kTLVType_State => <<4>>, @kTLVType_Proof => hash(a <> m_1 <> k)}
        state = %HAP.PairingStates.PairingM4{}
        {:ok, response, state}

      _ ->
        response = %{@kTLVType_State => <<4>>, @kTLVType_Error => @kTLVError_Authentication}
        {:ok, response, state}
    end
  end

  @doc """
  Handles `<M5>` messages and returns `<M6>` messages
  """
  def handle_message(
        %{@kTLVType_State => <<5>>, @kTLVType_EncryptedData => encrypted_data},
        %HAP.PairingStates.PairingM4{}
      ) do
    encrypted_data_length = byte_size(encrypted_data) - 16
    <<encrypted_data::binary-size(encrypted_data_length), auth_tag::binary-size(16)>> = encrypted_data

    IO.inspect(encrypted_data, label: "ED", limit: :infinity)
    IO.inspect(auth_tag, label: "Auth", limit: :infinity)

    response = %{@kTLVType_State => <<6>>}
    state = %{}
    {:ok, response, state}
  end

  def handle_message(tlv, state) do
    Logger.error("Received unexpected message for pairing state. Message: #{inspect(tlv)}, state: #{inspect(state)}")
    {:error, "Unexpected message for pairing state"}
  end

  defp hash(x), do: :crypto.hash(:sha512, x)
  defp to_bin(val) when is_integer(val), do: :binary.encode_unsigned(val)
  defp to_int(val) when is_bitstring(val), do: :binary.decode_unsigned(val)
end
