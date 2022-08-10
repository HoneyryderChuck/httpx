# frozen_string_literal: true

module Requests
  module Plugins
    module WebDav
      def test_plugin_webdav_mkcol
        # put file
        webdav_client.delete("/mkcol_dir_test/")

        response = webdav_client.mkcol("/mkcol_dir_test/")
        verify_status(response, 201)
      end

      def test_plugin_webdav_copy
        # put file
        webdav_client.delete("/copied_copy.html")
        webdav_client.put("/copy.html", body: "<html></html>")

        response = webdav_client.get("/copied_copy.html")
        verify_status(response, 404)
        response = webdav_client.copy("/copy.html", "/copied_copy.html")
        verify_status(response, 201)
        response = webdav_client.get("/copied_copy.html")
        verify_status(response, 200)
        response = webdav_client.get("/copy.html")
        verify_status(response, 200)
      end

      def test_plugin_webdav_move
        # put file
        webdav_client.delete("/moved_move.html")
        webdav_client.put("/move.html", body: "<html></html>")

        response = webdav_client.get("/moved_move.html")
        verify_status(response, 404)
        response = webdav_client.move("/move.html", "/moved_move.html")
        verify_status(response, 201)
        response = webdav_client.get("/move.html")
        verify_status(response, 404)
        response = webdav_client.get("/moved_move.html")
        verify_status(response, 200)
      end

      def test_plugin_webdav_lock
        # put file
        webdav_client.put("/lockfile.html", body: "bang")
        response = webdav_client.lock("/lockfile.html")
        verify_status(response, 200)
        lock_token = response.headers["lock-token"]

        response = webdav_client.delete("/lockfile.html")
        verify_status(response, 423)

        response = webdav_client.unlock("/lockfile.html", lock_token)
        verify_status(response, 204)

        response = webdav_client.delete("/lockfile.html")
        verify_status(response, 204)
      end

      def test_plugin_webdav_lock_blk
        # put file
        webdav_client.put("/lockfileblk.html", body: "bang")
        webdav_client.lock("/lockfileblk.html") do |response|
          verify_status(response, 200)

          response = webdav_client.delete("/lockfileblk.html")
          verify_status(response, 423)
        end
        response = webdav_client.delete("/lockfileblk.html")
        verify_status(response, 204)
      end

      def test_plugin_webdav_propfind_proppatch
        # put file
        webdav_client.put("/propfind.html", body: "bang")
        response = webdav_client.propfind("/propfind.html")
        verify_status(response, 207)
        xml = "<D:set>" \
              "<D:prop>" \
              "<Z:Authors>" \
              "<Z:Author>Jim Bean</Z:Author>" \
              "</Z:Authors>" \
              "</D:prop>" \
              "</D:set>"
        response = webdav_client.proppatch("/propfind.html", xml)
        verify_status(response, 207)

        response = webdav_client.propfind("/propfind.html")
        verify_status(response, 207)
        assert response.to_s.include?("Jim Bean")
      end

      private

      def webdav_client
        @webdav_client ||= HTTPX.plugin(:basic_authentication).plugin(:webdav, origin: start_webdav_server).basic_auth("user", "pass")
      end

      def start_webdav_server
        origin = ENV.fetch("WEBDAV_HOST")
        "http://#{origin}"
      end
    end
  end
end
