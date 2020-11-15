defmodule HAP.Accessory do
  @moduledoc """
  Represents a single accessory object, containing a number of services
  """

  defstruct services: []

  def build_accessory(accessory) do
    {[services: services], metadata} = Keyword.split(accessory, [:services])

    %__MODULE__{
      services:
        [HAP.Services.AccessoryInformation.build_service(metadata), HAP.Services.ProtocolInformation.build_service()] ++
          services
    }
  end

  def accessories_tree(%__MODULE__{services: services}, aid, opts \\ []) do
    formatted_services =
      services
      |> Enum.with_index()
      |> Enum.map(fn {service, service_index} ->
        HAP.Service.accessories_tree(service, service_index, opts)
      end)

    %{aid: aid, services: formatted_services}
  end

  def get_characteristic(%__MODULE__{services: services}, iid) do
    services
    |> Enum.at(HAP.IID.service_index(iid))
    |> HAP.Service.get_characteristic(iid)
  end
end